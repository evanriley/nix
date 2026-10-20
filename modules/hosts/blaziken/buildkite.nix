{ config, ... }:
let
  inherit (config.meta)
    secrets
    gerritKnownHosts
    projects
    buildkiteJobPackages
    ;
  mirroredProjects = builtins.filter (project: project ? mirror) projects;
  mirrorKeySecret = project: "${project.name}-mirror-key";
  untrustedAgent = "buildkite-agent-blaziken";
  mainAgent = "buildkite-agent-main";
  fallbackAgent = "buildkite-agent-spot-fallback";
  agents = [
    untrustedAgent
    mainAgent
  ];
in
{
  flake.modules.nixos.blaziken =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      mainHome = config.services.buildkite-agents.main.dataDir;
      secretPath = name: config.age.secrets.${name}.path;
      mirrorKeyExports = lib.concatMapStringsSep "\n" (
        project: "export ${lib.toUpper project.name}_MIRROR_KEY=${secretPath (mirrorKeySecret project)}"
      ) mirroredProjects;
      gerritKnownHostsFile = pkgs.writeText "gerrit-known-hosts" "${gerritKnownHosts}\n";
      githubKnownHosts = pkgs.writeText "github-known-hosts" ''
        github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
      '';
      gerritSsh = "ssh -i ${secretPath "gerrit-ci-key"} -o IdentitiesOnly=yes -o UserKnownHostsFile=${gerritKnownHostsFile} -o StrictHostKeyChecking=yes";

      mainJob = pkgs.writeShellApplication {
        name = "buildkite-main-job";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.gawk
          pkgs.git
          pkgs.jq
          pkgs.openssh
        ];
        text = ''
          job_id=$1
          build_number=$2
          mirror=${mainHome}/maybe.git
          checkout=${mainHome}/publish
          build_url="https://buildkite.com/riley-industries/maybe/builds/$build_number"

          if ! [[ $build_number =~ ^[0-9]+$ ]]; then
            echo "BUILDKITE_BUILD_NUMBER is '$build_number', expected a build number. The main agent looks up the job's build by it; run the job from a Buildkite build" >&2
            exit 1
          fi

          if ! build=$(printf 'Authorization: Bearer %s\n' "$(<${secretPath "buildkite-rest-token"})" \
            | curl -fsS --retry 3 -H @- "https://api.buildkite.com/v2/organizations/riley-industries/pipelines/maybe/builds/$build_number"); then
            echo "fetching build $build_number from the Buildkite REST API failed; the main agent needs it to verify job $job_id. Check buildkite-rest-token and api.buildkite.com, then retry the job" >&2
            exit 1
          fi

          if ! jq -e --arg job "$job_id" 'any(.jobs[]?; .id == $job)' <<<"$build" >/dev/null; then
            echo "job $job_id is not in build $build_number, so BUILDKITE_BUILD_NUMBER does not belong to this job. Not voting or publishing; retry the job from its own build" >&2
            exit 1
          fi

          commit=$(jq -r '.commit // ""' <<<"$build")
          if ! [[ $commit =~ ^[0-9a-f]{40}$ ]]; then
            echo "build $build_number has commit '$commit', expected a full 40-character sha. Create the build with the commit's full sha" >&2
            exit 1
          fi

          git init --quiet --bare "$mirror"
          git -C "$mirror" symbolic-ref HEAD refs/heads/main
          if ! GIT_SSH_COMMAND="${gerritSsh}" git -C "$mirror" fetch --quiet --no-tags \
            ssh://buildkite@git.maybemaybe.lol:29418/maybe +refs/heads/main:refs/heads/main; then
            echo "fetching refs/heads/main from Gerrit into $mirror failed; the main agent needs it to tell main commits from patchsets. Check gerrit-ci-key and git.maybemaybe.lol:29418, then retry the job" >&2
            exit 1
          fi

          on_main=false
          if git -C "$mirror" cat-file -e "$commit^{commit}" 2>/dev/null; then
            if git -C "$mirror" merge-base --is-ancestor "$commit" refs/heads/main; then
              on_main=true
            else
              status=$?
              if [ "$status" -ne 1 ]; then
                echo "checking whether $commit is on Gerrit main failed with status $status, expected 0 or 1. Check $mirror, then retry the job" >&2
                exit 1
              fi
            fi
          fi

          publish() {
            echo "--- publishing $commit from Gerrit main"
            rm -rf "$checkout"
            git clone --quiet --no-checkout "$mirror" "$checkout"
            git -C "$checkout" checkout --quiet --detach "$commit"
            cd "$checkout"
            CACHIX_AUTH_TOKEN=$(<${secretPath "cachix-token"})
            ORCA_CACHIX_TOKEN=$(<${secretPath "orca-cachix-token"})
            export CACHIX_AUTH_TOKEN ORCA_CACHIX_TOKEN
            ${mirrorKeyExports}
            export GITHUB_KNOWN_HOSTS=${githubKnownHosts}
            export CI_BUILDER_SYSTEM_FILE=${mainHome}/ci-builder-system
            export CI_REMOTE_BUILDER_SYSTEM_FILE=${mainHome}/ci-remote-builder-system
            export CI_REMOTE_BUILDER=1 BUILDKITE_JOB_ID="$job_id"
            exec .buildkite/ci.sh publish
          }

          report() {
            local failed_jobs verdict icon vote build_source patchset branch
            failed_jobs=$(jq -r --arg job "$job_id" '.jobs[] | select(.id != $job and .retried != true and (.state | IN("failed", "canceled", "timed_out", "expired", "broken"))) | "\(.name // .id): \(.state)"' <<<"$build")
            if [ -z "$failed_jobs" ]; then
              verdict=passed icon=✅ vote=1
            else
              verdict=failed icon=❌ vote=-1
            fi
            echo "--- build $build_number $verdict for $commit"
            if [ -n "$failed_jobs" ]; then
              printf '%s\n' "$failed_jobs"
            fi

            build_source=$(jq -r '.source // ""' <<<"$build")
            if [ "$build_source" != api ]; then
              echo "build $build_number was created by '$build_source', not by ci-trigger through the API, so it has no Gerrit patchset to vote on; reporting $verdict without voting"
            else
              patchset=$(jq -r '.env.GERRIT_PATCHSET // ""' <<<"$build")
              branch=$(jq -r '.branch // ""' <<<"$build")
              if ! [[ $patchset =~ ^([0-9]+),[0-9]+$ ]] || [ "$branch" != "cl/''${BASH_REMATCH[1]}" ]; then
                echo "build $build_number has GERRIT_PATCHSET '$patchset' on branch '$branch', expected '<change>,<patchset>' on cl/<change>. Not voting; create patchset builds through ci-trigger" >&2
                exit 1
              fi
              if ! jq -n --arg verdict "$verdict" --arg icon "$icon" --arg url "$build_url" --argjson vote "$vote" \
                '{message: "CI: \($verdict) \($icon) \($url)", labels: {Verified: $vote}, reviewers: [{reviewer: "buildkite"}]}' \
                | ${gerritSsh} -p 29418 buildkite@git.maybemaybe.lol gerrit review --project maybe --branch main --json "$commit"; then
                echo "voting Verified $vote on $commit (change $patchset) failed; expected Gerrit to accept the review. Check gerrit-ci-key and the buildkite account's permissions, then retry the job" >&2
                exit 1
              fi
            fi
            [ "$verdict" = passed ]
          }

          if [ "$on_main" = true ]; then
            publish
          else
            report
          fi
        '';
      };

      nightlyBuild = pkgs.writeShellApplication {
        name = "ci-nightly";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.git
          pkgs.jq
          pkgs.openssh
        ];
        text = ''
          builds_url=https://api.buildkite.com/v2/organizations/riley-industries/pipelines/maybe/builds
          poll_seconds=60

          buildkite() {
            printf 'Authorization: Bearer %s\n' "$(<${secretPath "buildkite-rest-token"})" \
              | curl -fsS -H @- "$@"
          }

          if ! refs=$(GIT_SSH_COMMAND="${gerritSsh}" git ls-remote \
            ssh://buildkite@git.maybemaybe.lol:29418/maybe refs/heads/main); then
            echo "reading refs/heads/main from Gerrit failed; the nightly build needs main's commit. Check gerrit-ci-key and git.maybemaybe.lol:29418, then start ci-nightly.service again" >&2
            exit 1
          fi
          commit=$(cut -f1 <<<"$refs")
          if ! [[ $commit =~ ^[0-9a-f]{40}$ ]]; then
            echo "Gerrit returned '$commit' for refs/heads/main, expected a full 40-character sha. Check that refs/heads/main exists in the maybe project, then start ci-nightly.service again" >&2
            exit 1
          fi

          body=$(jq -n --arg commit "$commit" \
            '{commit: $commit, branch: "main", message: "nightly \($commit[:12])", env: {CI_FULL: "1"}}')
          if ! build=$(buildkite -X POST -H 'Content-Type: application/json' --data-binary "$body" "$builds_url"); then
            echo "creating a nightly build of $commit through the Buildkite REST API failed. Check buildkite-rest-token and api.buildkite.com, then start ci-nightly.service again" >&2
            exit 1
          fi
          number=$(jq -r '.number // ""' <<<"$build")
          if ! [[ $number =~ ^[0-9]+$ ]]; then
            echo "Buildkite answered the build request for $commit with build number '$number', expected a number. Check the pipeline's builds on buildkite.com before starting ci-nightly.service again" >&2
            exit 1
          fi
          echo "started nightly build $number of $commit: $(jq -r '.web_url' <<<"$build")"

          while true; do
            sleep "$poll_seconds"
            if ! build=$(buildkite --retry 3 "$builds_url/$number"); then
              echo "fetching nightly build $number from the Buildkite REST API failed; the build may still be running. Check buildkite-rest-token and api.buildkite.com, then read the build on buildkite.com" >&2
              exit 1
            fi
            [ -z "$(jq -r '.finished_at // ""' <<<"$build")" ] || break
          done

          state=$(jq -r '.state' <<<"$build")
          if [ "$state" = passed ]; then
            echo "nightly build $number of $commit passed"
            exit 0
          fi
          echo "nightly build $number of $commit finished $state, expected passed. Failed jobs:" >&2
          jq -r '.jobs[] | select(.retried != true and (.state | IN("failed", "canceled", "timed_out", "expired", "broken"))) | "  \(.name // .id): \(.state)"' <<<"$build" >&2
          exit 1
        '';
      };

      flakeUpdate = pkgs.writeShellApplication {
        name = "ci-flake-update";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gawk
          pkgs.git
          pkgs.jq
          pkgs.openssh
          config.nix.package
        ];
        text = ''
          remote=$FLAKE_UPDATE_REMOTE
          gerrit_destination=$FLAKE_UPDATE_GERRIT
          workdir=$FLAKE_UPDATE_WORKDIR
          reviewer=$FLAKE_UPDATE_REVIEWER
          read -ra ssh_command <<<"$FLAKE_UPDATE_SSH"
          projects=(${lib.escapeShellArgs (map (project: project.name) projects)})
          export GIT_AUTHOR_NAME=Buildkite GIT_AUTHOR_EMAIL=buildkite@maybemaybe.lol
          export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL

          open_update_changes() {
            local rows
            if ! rows=$("''${ssh_command[@]}" "$gerrit_destination" gerrit query --format=JSON \
              project:maybe status:open owner:buildkite 'topic:^flake-update-.*') \
              || ! jq -e -s 'all(.type != "error")' <<<"$rows" >/dev/null; then
              printf '%s\n' "''${rows:-}" >&2
              echo "querying Gerrit for open flake-update changes failed; without it the run could stack a second chain on the open one. Check gerrit-ci-key and git.maybemaybe.lol:29418, then start ci-flake-update.service again" >&2
              return 1
            fi
            jq -r 'select(.type != "stats") | "\(.number) \(.topic)"' <<<"$rows"
          }

          update_inputs() {
            local project=$1 root_inputs inputs=()
            if [ "$project" = nix ]; then
              if ! root_inputs=$(jq -r '.nodes.root.inputs | keys[] | select(. != "berkeley-mono")' nix/flake.lock) \
                || [ -z "$root_inputs" ]; then
                echo "reading the root inputs from nix/flake.lock failed or found none; updating nix without them would also update berkeley-mono. Check nix/flake.lock on main" >&2
                return 1
              fi
              mapfile -t inputs <<<"$root_inputs"
            fi
            nix flake update --flake "./$project" "''${inputs[@]}"
          }

          open_changes=$(open_update_changes)
          if [ -n "$open_changes" ]; then
            echo "flake-update changes are still open; skipping this run until they merge or are abandoned:"
            printf '%s\n' "$open_changes"
            exit 0
          fi

          rm -rf "$workdir"
          if ! git clone --quiet --branch main -c core.sshCommand="$FLAKE_UPDATE_SSH" "$remote" "$workdir"; then
            echo "cloning main from $remote into $workdir failed. Check gerrit-ci-key and git.maybemaybe.lol:29418, then start ci-flake-update.service again" >&2
            exit 1
          fi
          cd "$workdir"

          refspecs=()
          for project in "''${projects[@]}"; do
            echo "--- updating $project"
            if ! update_log=$(update_inputs "$project" 2>&1); then
              printf '%s\n' "$update_log" >&2
              echo "nix flake update for $project failed; no changes were pushed. Fix the error above, then start ci-flake-update.service again" >&2
              exit 1
            fi
            printf '%s\n' "$update_log"

            if git diff --quiet -- "$project/flake.lock"; then
              echo "$project/flake.lock matches main"
              continue
            fi

            change_id=I$(od -An -N20 -tx1 /dev/urandom | tr -d ' \n')
            updates=$(awk '/^• / { keep = 1; print; next } keep && /^ / { print; next } { keep = 0 }' <<<"$update_log")
            printf 'build(%s): update flake inputs\n\n%s\n\nChange-Id: %s\n' "$project" "$updates" "$change_id" \
              | git commit --quiet --file=- -- "$project/flake.lock"
            refspecs+=("$(git rev-parse HEAD):refs/for/main%topic=flake-update-$project,l=Autosubmit+1,r=$reviewer")
          done

          if [ "''${#refspecs[@]}" -eq 0 ]; then
            echo "no flake.lock changed; nothing to push"
            exit 0
          fi
          for refspec in "''${refspecs[@]}"; do
            echo "--- pushing $refspec"
            if ! git push --quiet origin "$refspec"; then
              echo "pushing $refspec to $remote failed; changes below it in the chain may already be open. Check the error above, then start ci-flake-update.service again" >&2
              exit 1
            fi
          done
        '';
      };

      gracefulReload = agent: {
        # Restarting on activation kills the running job; SIGTERM lets it finish first.
        reloadIfChanged = true;
        restartTriggers = [ (builtins.hashFile "sha256" config.age.secrets.buildkite-token.file) ];
        serviceConfig = {
          RuntimeDirectory = agent;
          ExecReload = "${
            pkgs.writeShellApplication {
              name = "${agent}-stop-gracefully";
              runtimeInputs = [ pkgs.coreutils ];
              text = ''
                main_pid="$1"
                marker="$RUNTIME_DIRECTORY/graceful-stop-$main_pid"
                if [ ! -e "$marker" ]; then
                  touch "$marker"
                  kill -TERM "$main_pid" || true
                fi
              '';
            }
          }/bin/${agent}-stop-gracefully $MAINPID";
        };
      };

      loopbackServicePorts = "1411,1414,4180,6070,8080,8081,8082,8083,8084,8470";
      blockLoopbackRules = map (
        agent:
        "OUTPUT -o lo -p tcp -m multiport --dports ${loopbackServicePorts} -m owner --uid-owner ${agent} -j REJECT --reject-with tcp-reset"
      ) agents;
      deleteRule = rule: "iptables -w -D ${rule} 2>/dev/null || true\n";

      untrustedAgentSettings = {
        tokenPath = config.age.secrets.buildkite-token.path;
        extraGroups = [ ];
        runtimePackages = buildkiteJobPackages pkgs config.nix.package;
      };
      untrustedService = {
        environment.CMAKE_BUILD_PARALLEL_LEVEL = "4";
        serviceConfig = {
          CPUWeight = 20;
          OOMScoreAdjust = 500;
        };
      };
    in
    {
      services.buildkite-agents.blaziken = untrustedAgentSettings // {
        name = "%hostname-%spawn";
        extraConfig = "spawn=2";
        # The monorepo is public; pipelines clone over https without credentials.
        tags = {
          queue = "blaziken";
          host = "blaziken";
        };
      };

      services.buildkite-agents.spot-fallback = untrustedAgentSettings // {
        name = "%hostname-spot-fallback";
        extraConfig = ''
          spawn=1
          disconnect-after-idle-timeout=300
        '';
        tags = {
          queue = "spot-builders";
          host = "blaziken";
        };
      };

      users.users.${fallbackAgent}.enable = false;

      services.buildkite-agents.main = {
        tokenPath = config.age.secrets.buildkite-token.path;
        name = "%hostname-main";
        extraConfig = ''
          spawn=1
          no-plugins=true
          no-local-hooks=true
          enable-environment-variable-allowlist=true
          allowed-environment-variables=^GERRIT_MERGE$,^GERRIT_PATCHSET$,^CI_FULL$,^CI_EVAL_JOBS$,^CI_HEAVY_QUEUE$
        '';
        extraGroups = [ ];
        tags = {
          queue = "main";
          host = "blaziken";
        };
        runtimePackages = [
          pkgs.bash
          pkgs.git
          pkgs.openssh
          pkgs.curl
          pkgs.jq
          pkgs.cachix
          pkgs.josh
          pkgs.lixPackageSets.stable.nix-eval-jobs
          config.nix.package
          pkgs.coreutils
        ];
        hooks = {
          pre-bootstrap = ''
            claimed=$(jq -r '.BUILDKITE_JOB_ID // ""' "$BUILDKITE_ENV_JSON_FILE")
            if [ "$claimed" != "$BUILDKITE_JOB_ID" ]; then
              echo "rejecting job $BUILDKITE_JOB_ID: its environment has BUILDKITE_JOB_ID '$claimed', expected the id of the job this agent accepted. The main agent's hooks identify the job by it; remove BUILDKITE_JOB_ID from the step's env" >&2
              exit 1
            fi
            reserved=$(jq -r '[to_entries[] | select(.value != "" and (.key | test("^BUILDKITE_(BOOTSTRAP_PHASES|PLUGINS|USE_REPOSITORY_PROVIDER_GIT_CREDENTIALS|USE_GITHUB_APP_GIT_CREDENTIALS)$"))) | .key] | join(", ")' "$BUILDKITE_ENV_JSON_FILE")
            if [ -n "$reserved" ]; then
              echo "rejecting job $BUILDKITE_JOB_ID: its environment sets $reserved, which would skip the main agent's hooks or rewrite its git configuration. Remove them from the step's env" >&2
              exit 1
            fi
          '';
          environment = ''
            export BUILDKITE_ARTIFACT_PATHS=""
            export BUILDKITE_SKIP_CHECKOUT=true
            export BUILDKITE_CLEAN_CHECKOUT=false
            export BUILDKITE_BUILD_CHECKOUT_PATH=${mainHome}/builds/job
          '';
          checkout = ''
            echo "the main agent does not check out the job's repository; the command hook fetches the verified commit from Gerrit"
          '';
          command = ''
            env -i HOME=${mainHome} PATH="$PATH" NIX_REMOTE=daemon \
              ${mainJob}/bin/buildkite-main-job "$BUILDKITE_JOB_ID" "''${BUILDKITE_BUILD_NUMBER:-}"
          '';
        };
      };

      systemd.services = lib.mkMerge [
        (lib.genAttrs (agents ++ [ fallbackAgent ]) gracefulReload)
        (lib.genAttrs agents (_: {
          serviceConfig.Restart = lib.mkForce "always";
        }))
        {
          ${untrustedAgent} = untrustedService;

          ${fallbackAgent} = lib.mkMerge [
            untrustedService
            {
              wantedBy = lib.mkForce [ ];
              serviceConfig = {
                User = lib.mkForce untrustedAgent;
                Group = untrustedAgent;
                StateDirectory = fallbackAgent;
                StateDirectoryMode = "0700";
                Restart = lib.mkForce "no";
              };
            }
          ];

          nix-daemon.serviceConfig.CPUWeight = 20;
        }
        {
          ci-nightly = {
            description = "Run a full Buildkite build of Gerrit main";
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            serviceConfig = {
              Type = "oneshot";
              User = mainAgent;
              Group = mainAgent;
              ExecStart = "${nightlyBuild}/bin/ci-nightly";
              TimeoutStartSec = "6h";
            };
          };

          ci-flake-update = {
            description = "Open Gerrit changes that update the flake.lock files";
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            environment = {
              FLAKE_UPDATE_REMOTE = "ssh://buildkite@git.maybemaybe.lol:29418/maybe";
              FLAKE_UPDATE_GERRIT = "ssh://buildkite@git.maybemaybe.lol:29418";
              FLAKE_UPDATE_SSH = gerritSsh;
              FLAKE_UPDATE_WORKDIR = "${mainHome}/flake-update";
              FLAKE_UPDATE_REVIEWER = "evan";
            };
            serviceConfig = {
              Type = "oneshot";
              User = mainAgent;
              Group = mainAgent;
              ExecStart = "${flakeUpdate}/bin/ci-flake-update";
              TimeoutStartSec = "2h";
            };
          };
        }
      ];

      systemd.timers.ci-nightly = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 03:00";
          Persistent = true;
        };
      };

      systemd.timers.ci-flake-update = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 04:00";
          Persistent = true;
        };
      };

      networking.firewall = {
        extraCommands = lib.concatMapStrings (
          rule: deleteRule rule + "iptables -w -I ${rule}\n"
        ) blockLoopbackRules;
        extraStopCommands = lib.concatMapStrings deleteRule blockLoopbackRules;
      };

      nix.settings = {
        max-jobs = 1;
        cores = 4;
      };

      age.secrets =
        lib.genAttrs (map mirrorKeySecret mirroredProjects) (name: {
          file = secrets + "/blaziken/${name}.age";
          owner = mainAgent;
        })
        // {
          buildkite-token = {
            file = secrets + "/blaziken/buildkite-token.age";
            owner = mainAgent;
            group = untrustedAgent;
            mode = "0440";
          };

          cachix-token = {
            file = secrets + "/blaziken/cachix-token.age";
            owner = mainAgent;
          };

          buildkite-rest-token = {
            file = secrets + "/blaziken/buildkite-rest-token.age";
            owner = mainAgent;
          };

          gerrit-ci-key = {
            file = secrets + "/blaziken/gerrit-ci-key.age";
            owner = mainAgent;
          };

          orca-cachix-token = {
            file = secrets + "/blaziken/orca-cachix-token.age";
            owner = mainAgent;
          };

          gcp-ci-key = {
            file = secrets + "/blaziken/gcp-ci-key.age";
            owner = mainAgent;
          };
        };
    };
}
