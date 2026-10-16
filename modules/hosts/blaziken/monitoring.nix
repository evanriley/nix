{ config, ... }:
let
  inherit (config.meta) secrets;

  domain = "maybemaybe.lol";

  disks = [
    "/dev/disk/by-id/ata-HGST_HUS724020ALA640_PN2134P6HDTRJP"
    "/dev/disk/by-id/ata-HGST_HUS724020ALA640_PN1134P6HHXZZN"
  ];

  units = [
    "nginx.service"
    "gerrit.service"
    "git-bug-webui.service"
    "ci-trigger.service"
    "anubis-homepage.service"
    "anubis-code.service"
    "anubis-bugs.service"
    "anubis-search.service"
    "buildkite-agent-blaziken.service"
    "zoekt-webserver.service"
    "zoekt-index.timer"
  ];

  sites = [
    domain
    "git.${domain}"
    "code.${domain}"
    "bugs.${domain}"
    "cs.${domain}"
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
      mkPing =
        name: urlFile:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [
            pkgs.coreutils
            pkgs.curl
          ];
          text = ''
            url="$(tr -d '[:space:]' < ${urlFile})"
            case "$1" in
              ok) ;;
              fail) url="$url/fail" ;;
              *) echo "usage: ${name} ok|fail (body on stdin)" >&2; exit 2 ;;
            esac
            curl -fsS -m 10 --retry 3 --data-binary @- "$url" > /dev/null
          '';
        };

      heartbeatPing = mkPing "healthchecks-heartbeat-ping" config.age.secrets.healthchecks-heartbeat.path;
      disksPing = mkPing "healthchecks-disks-ping" config.age.secrets.healthchecks-disks.path;

      rootArray = "/dev/md/root";

      collectDegraded = ''
        for degraded in /sys/block/md*/md/degraded; do
          [ -e "$degraded" ] || continue
          if [ "$(cat "$degraded")" != 0 ]; then
            md="$(basename "$(dirname "$(dirname "$degraded")")")"
            failures+=("md array $md is degraded")
          fi
        done
      '';

      report = ping: ''
        if [ "''${#failures[@]}" -eq 0 ]; then
          ${ping} ok < /dev/null
        else
          printf '%s\n' "''${failures[@]}" | ${ping} fail
        fi
      '';

      heartbeat = pkgs.writeShellApplication {
        name = "blaziken-heartbeat";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.systemd
        ];
        text = ''
          failures=()

          ${collectDegraded}

          failed="$(systemctl --failed --plain --no-legend)"
          if [ -n "$failed" ]; then
            failures+=("failed units: $failed")
          fi

          for unit in ${lib.escapeShellArgs units}; do
            if ! systemctl is-active --quiet "$unit"; then
              failures+=("$unit is not active")
            fi
          done

          for site in ${lib.escapeShellArgs sites}; do
            code="$(curl -sS -o /dev/null -m 15 -w '%{http_code}' \
              --resolve "$site:443:127.0.0.1" "https://$site/")" || code=000
            case "$code" in
              2?? | 3?? | 401) ;;
              *) failures+=("https://$site/ returned $code") ;;
            esac
          done

          ${report "${heartbeatPing}/bin/healthchecks-heartbeat-ping"}
        '';
      };

      diskHealth = pkgs.writeShellApplication {
        name = "blaziken-disk-health";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.smartmontools
        ];
        text = ''
          failures=()

          for disk in ${lib.escapeShellArgs disks}; do
            if ! output="$(smartctl -H "$disk" 2>&1)"; then
              failures+=("smartctl -H $disk failed: $output")
            fi
          done

          ${collectDegraded}

          if [ ! -e ${rootArray} ]; then
            failures+=("${rootArray} does not exist")
          else
            md="$(basename "$(readlink -f ${rootArray})")"
            mismatches="$(cat "/sys/block/$md/md/mismatch_cnt")"
            if [ "$mismatches" != 0 ]; then
              failures+=("$md mismatch_cnt is $mismatches")
            fi
          fi

          ${report "${disksPing}/bin/healthchecks-disks-ping"}
        '';
      };

      scrub = pkgs.writeShellApplication {
        name = "blaziken-raid-scrub";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          md="$(basename "$(readlink -f ${rootArray})")"
          echo check > "/sys/block/$md/md/sync_action"
        '';
      };

      mdadmAlert = pkgs.writeShellApplication {
        name = "blaziken-mdadm-alert";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          event="$1"
          device="''${2:-}"
          component="''${3:-}"
          case "$event" in
            Fail | FailSpare | DegradedArray | DeviceDisappeared)
              echo "mdadm $event on $device $component" | ${disksPing}/bin/healthchecks-disks-ping fail
              ;;
            *) ;;
          esac
        '';
      };

      smartdMailer = pkgs.writeShellApplication {
        name = "blaziken-smartd-mailer";
        text = "exec ${disksPing}/bin/healthchecks-disks-ping fail";
      };
    in
    {
      age.secrets.healthchecks-heartbeat.file = secrets + "/blaziken/healthchecks-heartbeat.age";
      age.secrets.healthchecks-disks.file = secrets + "/blaziken/healthchecks-disks.age";

      boot.swraid.mdadmConf = "PROGRAM ${mdadmAlert}/bin/blaziken-mdadm-alert";

      services.smartd = {
        enable = true;
        notifications.mail = {
          enable = true;
          mailer = "${smartdMailer}/bin/blaziken-smartd-mailer";
        };
      };

      systemd.services.blaziken-heartbeat = {
        description = "Ping healthchecks.io when blaziken is healthy";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${heartbeat}/bin/blaziken-heartbeat";
        };
      };
      systemd.timers.blaziken-heartbeat = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitActiveSec = "5min";
        };
      };

      systemd.services.blaziken-disk-health = {
        description = "Ping healthchecks.io when disks and arrays are healthy";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${diskHealth}/bin/blaziken-disk-health";
        };
      };
      systemd.timers.blaziken-disk-health = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };

      systemd.services.blaziken-raid-scrub = {
        description = "Scrub the root RAID array";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${scrub}/bin/blaziken-raid-scrub";
        };
      };
      systemd.timers.blaziken-raid-scrub = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "monthly";
          Persistent = true;
        };
      };
    };
}
