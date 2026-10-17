{ config, ... }:
let
  inherit (config.meta) secrets;
  untrustedAgent = "buildkite-agent-blaziken";
  mainAgent = "buildkite-agent-main";
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
      gerritKnownHosts = pkgs.writeText "gerrit-known-hosts" ''
        [git.maybemaybe.lol]:29418 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHGOzrLcNC9G05r/TC3Gldb+gKLK+OZwmLN0xKVE2RIO
      '';
      githubKnownHosts = pkgs.writeText "github-known-hosts" ''
        github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
      '';
      gerritSsh = "ssh -i ${secretPath "gerrit-ci-key"} -o IdentitiesOnly=yes -o UserKnownHostsFile=${gerritKnownHosts} -o StrictHostKeyChecking=yes";

      mainJob = pkgs.writeShellApplication {
        name = "buildkite-main-job";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
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
            export ORCA_MIRROR_KEY=${secretPath "orca-mirror-key"}
            export MANTA_MIRROR_KEY=${secretPath "manta-mirror-key"}
            export NIX_MIRROR_KEY=${secretPath "nix-mirror-key"}
            export GITHUB_KNOWN_HOSTS=${githubKnownHosts}
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

      gracefulReload = agent: {
        # Restarting on activation kills the running job; SIGTERM lets it finish first.
        reloadIfChanged = true;
        serviceConfig = {
          Restart = lib.mkForce "always";
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

      loopbackServicePorts = "6070,8080,8081,8082,8083,8470";
      blockLoopbackRules = map (
        agent:
        "OUTPUT -o lo -p tcp -m multiport --dports ${loopbackServicePorts} -m owner --uid-owner ${agent} -j REJECT --reject-with tcp-reset"
      ) agents;
      deleteRule = rule: "iptables -w -D ${rule} 2>/dev/null || true\n";
    in
    {
      services.buildkite-agents.blaziken = {
        tokenPath = config.age.secrets.buildkite-token.path;
        name = "%hostname-%spawn";
        extraConfig = "spawn=2";
        extraGroups = [ ];
        # The monorepo is public; pipelines clone over https without credentials.
        tags = {
          queue = "blaziken";
          host = "blaziken";
        };
        runtimePackages = [
          pkgs.bash
          pkgs.git
          pkgs.curl
          pkgs.jq
          pkgs.josh
          pkgs.openssh
          config.nix.package
        ];
      };

      services.buildkite-agents.main = {
        tokenPath = config.age.secrets.buildkite-token.path;
        name = "%hostname-main";
        extraConfig = ''
          spawn=1
          no-plugins=true
          no-local-hooks=true
          enable-environment-variable-allowlist=true
          allowed-environment-variables=^GERRIT_MERGE$,^GERRIT_PATCHSET$,^CI_FULL$,^CI_EVAL_JOBS$
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

      systemd.services = lib.genAttrs agents gracefulReload;

      networking.firewall = {
        extraCommands = lib.concatMapStrings (
          rule: deleteRule rule + "iptables -w -I ${rule}\n"
        ) blockLoopbackRules;
        extraStopCommands = lib.concatMapStrings deleteRule blockLoopbackRules;
      };

      nix.settings = {
        max-jobs = 2;
        cores = 4;
      };

      age.secrets.buildkite-token = {
        file = secrets + "/blaziken/buildkite-token.age";
        owner = mainAgent;
        group = untrustedAgent;
        mode = "0440";
      };

      age.secrets.cachix-token = {
        file = secrets + "/blaziken/cachix-token.age";
        owner = mainAgent;
      };

      age.secrets.buildkite-rest-token = {
        file = secrets + "/blaziken/buildkite-rest-token.age";
        owner = mainAgent;
      };

      age.secrets.gerrit-ci-key = {
        file = secrets + "/blaziken/gerrit-ci-key.age";
        owner = mainAgent;
      };

      age.secrets.orca-mirror-key = {
        file = secrets + "/blaziken/orca-mirror-key.age";
        owner = mainAgent;
      };

      age.secrets.manta-mirror-key = {
        file = secrets + "/blaziken/manta-mirror-key.age";
        owner = mainAgent;
      };

      age.secrets.nix-mirror-key = {
        file = secrets + "/blaziken/nix-mirror-key.age";
        owner = mainAgent;
      };

      age.secrets.orca-cachix-token = {
        file = secrets + "/blaziken/orca-cachix-token.age";
        owner = mainAgent;
      };
    };
}
