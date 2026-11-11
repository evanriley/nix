{ config, ... }:
let
  inherit (config.meta) gerritKnownHosts domain;
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
      stateDirectory = "/var/lib/blaziken-deploy";
      secretPath = name: config.age.secrets.${name}.path;
      gerritKnownHostsFile = pkgs.writeText "gerrit-known-hosts" "${gerritKnownHosts}\n";
      gerritSsh = "ssh -i ${secretPath "gerrit-ci-key"} -o IdentitiesOnly=yes -o UserKnownHostsFile=${gerritKnownHostsFile} -o StrictHostKeyChecking=yes";

      deploy = pkgs.writeShellApplication {
        name = "blaziken-deploy";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.git
          pkgs.jq
          pkgs.openssh
          pkgs.util-linux
          config.nix.package
        ]
        ++ lib.attrValues config.bootTrial.commands;
        text = ''
          export LC_ALL=C

          state=${stateDirectory}
          repo=$state/maybe.git
          stamp=$state/backup-succeeded
          profile=/nix/var/nix/profiles/system
          main_builds_url="https://api.buildkite.com/v2/organizations/riley-industries/pipelines/maybe/builds?branch=main&per_page=100"
          health_check=${config.blaziken.healthCheck}/bin/blaziken-health-check
          max_backup_age_seconds=$((36 * 3600))
          settle_seconds=300
          settle_interval_seconds=30

          settle_boot() {
            boot-trial-fallback
            if [ "$(boot-identity /run/booted-system)" = "$(boot-identity /run/current-system)" ]; then
              echo "--- the booted system has the kernel, initrd, modules and parameters of $(readlink -f /run/current-system); pinning it"
              boot-trial-pin
            else
              echo "--- the booted system differs in kernel, initrd, modules or parameters from $(readlink -f /run/current-system); starting a kernel trial"
              boot-trial-start "$(readlink -f /run/current-system)"
            fi
          }

          usage() {
            echo "usage: blaziken-deploy [--toplevel PATH]" >&2
            exit 2
          }

          toplevel=""
          if [ "$#" -eq 2 ] && [ "$1" = --toplevel ]; then
            toplevel=$2
          elif [ "$#" -ne 0 ]; then
            usage
          fi

          if [ -n "$toplevel" ]; then
            if ! [ -x "$toplevel/bin/switch-to-configuration" ]; then
              echo "--toplevel '$toplevel' has no bin/switch-to-configuration, expected a NixOS system closure such as the output of nix build ...#nixosConfigurations.blaziken.config.system.build.toplevel. Build it, or copy it to blaziken, then run blaziken-deploy --toplevel again" >&2
              exit 1
            fi
            toplevel=$(readlink -f "$toplevel")
          fi

          exec 9> /run/blaziken-deploy.lock
          if ! flock -n 9; then
            echo "/run/blaziken-deploy.lock is held, so another blaziken-deploy is running; expected none. Wait for it to finish (systemctl status blaziken-deploy), then run blaziken-deploy again" >&2
            exit 1
          fi

          if [ -n "$toplevel" ]; then
            new=$toplevel
            label=$toplevel
          else
            git init --quiet --bare "$repo"
            git -C "$repo" symbolic-ref HEAD refs/heads/main
            if ! GIT_SSH_COMMAND="${gerritSsh}" git -C "$repo" fetch --quiet --no-tags \
              ssh://buildkite@git.${domain}:29418/maybe +refs/heads/main:refs/heads/main; then
              echo "fetching refs/heads/main from Gerrit into $repo failed; the deploy needs the tip of main. Check gerrit-ci-key and git.${domain}:29418, then start blaziken-deploy.service again" >&2
              exit 1
            fi
            commit=$(git -C "$repo" rev-parse refs/heads/main)
            if ! [[ $commit =~ ^[0-9a-f]{40}$ ]]; then
              echo "git rev-parse refs/heads/main in $repo printed '$commit', expected a full 40-character sha. Check $repo, then start blaziken-deploy.service again" >&2
              exit 1
            fi

            if ! builds=$(printf 'Authorization: Bearer %s\n' "$(<${secretPath "buildkite-rest-token"})" \
              | curl -fsS -m 30 --retry 3 -H @- "$main_builds_url&commit=$commit"); then
              echo "fetching the Buildkite builds of main tip $commit from the Buildkite REST API failed; the deploy needs their states. Check buildkite-rest-token and api.buildkite.com, then start blaziken-deploy.service again" >&2
              exit 1
            fi
            if ! states=$(jq -r --arg commit "$commit" '[.[] | select(.commit == $commit) | .state] | unique | join(" ")' <<< "$builds"); then
              echo "Buildkite returned '$builds' for the builds of main tip $commit, expected a JSON array of builds. Check buildkite-rest-token, then start blaziken-deploy.service again" >&2
              exit 1
            fi
            case " $states " in
              *" passed "*) ;;
              *" creating "* | *" scheduled "* | *" running "* | *" failing "* | *" canceling "*)
                echo "main tip $commit is still building in Buildkite (states: $states); nothing was deployed"
                exit 0
                ;;
              *)
                echo "main tip $commit has no passed Buildkite build (states: ''${states:-none}); expected the tip of main to have passed. Retry its build on buildkite.com or merge a fix, then start blaziken-deploy.service again" >&2
                exit 1
                ;;
            esac

            if ! new=$(nix build --no-link --print-out-paths \
              "git+file://$repo?dir=nix&rev=$commit#nixosConfigurations.blaziken.config.system.build.toplevel"); then
              echo "building the blaziken toplevel for $commit failed; expected the passed build to evaluate and build. Read the nix output above, then start blaziken-deploy.service again" >&2
              exit 1
            fi
            if ! [ -x "$new/bin/switch-to-configuration" ]; then
              echo "nix build printed '$new' for $commit, expected a system closure with bin/switch-to-configuration. Run nix build on the flake by hand and inspect the output" >&2
              exit 1
            fi
            label=$commit
          fi

          if [ "$(readlink -f "$new")" = "$(readlink -f /run/current-system)" ]; then
            echo "already running $label"
            settle_boot
            exit 0
          fi

          if ! [ -e "$stamp" ]; then
            echo "$stamp is missing, expected a borgmatic run to have touched it within 36 hours. Run systemctl start borgmatic and wait for it to succeed, then deploy again" >&2
            exit 1
          fi
          stamp_epoch=$(stat -c %Y "$stamp")
          if [ "$(($(date +%s) - stamp_epoch))" -gt "$max_backup_age_seconds" ]; then
            echo "the last successful backup was at $(date -d "@$stamp_epoch" '+%F %T %Z'), expected one within 36 hours. Run systemctl start borgmatic and wait for it to succeed, then deploy again" >&2
            exit 1
          fi

          lines() {
            if [ -n "$1" ]; then
              printf '%s\n' "$1"
            fi
          }

          current_failures() {
            local output
            output=$("$health_check" --deploy) || true
            lines "$output" | sort
          }

          new_failures_since() {
            comm -13 <(lines "$1") <(lines "$2")
          }

          echo "--- health check before deploying $label"
          before=$(current_failures)
          lines "$before"

          previous=$(readlink -f /run/current-system)

          echo "--- switching to $new"
          nix-env -p "$profile" --set "$new"
          switch_status=0
          "$new/bin/switch-to-configuration" switch || switch_status=$?

          echo "--- health check after switching to $new"
          deadline=$((SECONDS + settle_seconds))
          while true; do
            after=$(current_failures)
            new_failures=$(new_failures_since "$before" "$after")
            if [ -z "$new_failures" ] || [ "$switch_status" -ne 0 ] || [ "$SECONDS" -ge "$deadline" ]; then
              break
            fi
            sleep "$settle_interval_seconds"
          done

          if [ "$switch_status" -ne 0 ] || [ -n "$new_failures" ]; then
            echo "--- rolling back to $previous"
            echo "switch-to-configuration for $new exited with status $switch_status" >&2
            if [ -n "$new_failures" ]; then
              echo "new failures since before the deploy:" >&2
              lines "$new_failures" >&2
            fi
            if ! nix-env -p "$profile" --set "$previous" \
              || ! "$previous/bin/switch-to-configuration" switch; then
              echo "ROLLBACK FAILED: blaziken may be half-switched between $new and $previous. Log in over Tailscale and run: nix-env -p $profile --set $previous && $previous/bin/switch-to-configuration switch" >&2
              exit 1
            fi
            echo "rolled back to $previous after failing to deploy $label; expected a deploy with no new failures. Fix the cause, then start blaziken-deploy.service again" >&2
            exit 1
          fi

          echo "deployed $label"
          settle_boot
        '';
      };
    in
    {
      bootTrial = {
        healthCheck = config.blaziken.healthCheck;
        trialSeconds = 900;
        heartbeatParameter = "intel_oc_wdt.heartbeat";
        inherit stateDirectory;
        redeployUnit = "blaziken-deploy.service";
      };

      environment.systemPackages = [ deploy ];

      systemd.tmpfiles.rules = [ "d ${stateDirectory} 0700 root root -" ];

      systemd.services.blaziken-deploy = {
        description = "Deploy the tip of main to blaziken once its Buildkite build passed";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${deploy}/bin/blaziken-deploy";
          TimeoutStartSec = "2h";
          StateDirectory = "blaziken-deploy";
        };
      };

      systemd.timers.blaziken-deploy = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 06:30";
          Persistent = true;
        };
      };
    };
}
