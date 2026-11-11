{ config, ... }:
let
  inherit (config.meta) secrets domain;

  disks = [
    "/dev/disk/by-id/ata-HGST_HUS724020ALA640_PN2134P6HDTRJP"
    "/dev/disk/by-id/ata-HGST_HUS724020ALA640_PN1134P6HHXZZN"
  ];

  units = [
    "nginx.service"
    "gerrit.service"
    "git-bug-webui.service"
    "git-bug-webui-public.service"
    "oauth2-proxy.service"
    "pocket-id.service"
    "rustical.service"
    "phpfpm-roundcube.service"
    "ci-trigger.service"
    "ci-spot-poller.service"
    "anubis-homepage.service"
    "anubis-code.service"
    "anubis-git.service"
    "anubis-bugs.service"
    "anubis-bugs-public.service"
    "anubis-search.service"
    "buildkite-agent-blaziken.service"
    "buildkite-agent-main.service"
    "zoekt-webserver.service"
    "zoekt-index.timer"
    "postgresql.service"
    "postfix.service"
    "dovecot.service"
    "fail2ban.service"
    "rspamd.service"
    "redis-rspamd.service"
    "redis-newsblur.service"
    "podman-newsblur-mongo.service"
    "podman-newsblur-elasticsearch.service"
    "podman-newsblur-web.service"
    "podman-newsblur-celery.service"
    "podman-newsblur-node.service"
    "podman-newsblur-imageproxy.service"
    "newsblur-setup.service"
  ];

  ports = [
    22
    25
    465
    993
    4190
    29418
  ];

  sites = [
    {
      url = domain;
      expect = 200;
    }
    {
      url = "git.${domain}/config/server/version";
      expect = 200;
    }
    {
      url = "code.${domain}";
      expect = 302;
    }
    {
      url = "bugs.${domain}";
      expect = 200;
    }
    {
      url = "bugs-edit.${domain}";
      expect = 307;
    }
    {
      url = "cs.${domain}";
      expect = 200;
    }
    {
      url = "id.${domain}/.well-known/openid-configuration";
      expect = 200;
    }
    {
      url = "news.${domain}";
      expect = 200;
    }
    {
      url = "dav.${domain}/frontend/login";
      expect = 200;
    }
    {
      url = "mail.${domain}";
      expect = 200;
    }
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

      reverseOctets = address: lib.concatStringsSep "." (lib.reverseList (lib.splitString "." address));

      reverseNibbles =
        address:
        lib.concatStringsSep "." (
          lib.reverseList (
            lib.stringToCharacters (
              lib.concatMapStrings (lib.fixedWidthString 4 "0") (
                lib.splitString ":" (lib.network.ipv6.fromString address).address
              )
            )
          )
        );

      blocklistQueries =
        lib.concatMap (
          { address, ... }:
          map
            (zone: {
              inherit address zone;
              name = "${reverseOctets address}.${zone}";
            })
            [
              "zen.spamhaus.org"
              "bl.spamcop.net"
            ]
        ) config.networking.interfaces.eth0.ipv4.addresses
        ++ map (
          { address, ... }:
          {
            inherit address;
            zone = "zen.spamhaus.org";
            name = "${reverseNibbles address}.zen.spamhaus.org";
          }
        ) config.networking.interfaces.eth0.ipv6.addresses;

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
          printf '%s\n' "''${failures[@]}" >&2
          printf '%s\n' "''${failures[@]}" | ${ping} fail
        fi
      '';

      healthCheck = pkgs.writeShellApplication {
        name = "blaziken-health-check";
        runtimeInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.curl
          pkgs.jq
          pkgs.systemd
          config.services.tailscale.package
        ];
        text = ''
          deploy=false
          case "''${1:-}" in
            "") ;;
            --deploy) deploy=true ;;
            *) echo "usage: blaziken-health-check [--deploy]" >&2; exit 2 ;;
          esac

          failures=()

          while read -r unit _; do
            case "$unit" in
              ci-nightly.service | ci-flake-update.service | nix-daemon@*.service) ;;
              blaziken-deploy.service)
                if [ "$deploy" = false ]; then
                  failures+=("failed unit: $unit")
                fi
                ;;
              *) failures+=("failed unit: $unit") ;;
            esac
          done < <(systemctl --failed --plain --no-legend)

          inactive=()
          for unit in ${lib.escapeShellArgs units}; do
            if ! systemctl is-active --quiet "$unit"; then
              inactive+=("$unit")
            fi
          done
          if [ "''${#inactive[@]}" -gt 0 ]; then
            sleep 60
            for unit in "''${inactive[@]}"; do
              if ! systemctl is-active --quiet "$unit"; then
                failures+=("$unit is not active")
              fi
            done
          fi

          check_site() {
            local site="$1" expected="$2" host code
            host="''${site%%/*}"
            code="$(curl -sS -o /dev/null -m 15 -w '%{http_code}' \
              --resolve "$host:443:127.0.0.1" "https://$site")" || code=000
            if [ "$code" != "$expected" ]; then
              failures+=("https://$site returned $code, expected $expected")
            fi
          }
          ${lib.concatMapStrings (
            site: "check_site ${lib.escapeShellArg site.url} ${toString site.expect}\n"
          ) sites}

          for port in ${lib.escapeShellArgs (map toString ports)}; do
            if ! timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/\$1" _ "$port" 2> /dev/null; then
              failures+=("127.0.0.1:$port did not accept a TCP connection within 5s")
            fi
          done

          if ! tailscale_json="$(tailscale status --json 2> /dev/null)"; then
            failures+=("tailscale status --json failed; run it by hand to see why")
          elif ! backend_state="$(jq -r '.BackendState // ""' <<< "$tailscale_json")"; then
            failures+=("tailscale status --json returned output jq could not parse")
          elif [ "$backend_state" != Running ]; then
            failures+=("tailscale BackendState is '$backend_state', expected Running")
          fi

          if [ "''${#failures[@]}" -gt 0 ]; then
            printf '%s\n' "''${failures[@]}"
            exit 1
          fi
        '';
      };

      heartbeat = pkgs.writeShellApplication {
        name = "blaziken-heartbeat";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.dig
          pkgs.jq
          config.services.postfix.package
        ];
        text = ''
          failures=()

          ${collectDegraded}

          health_status=0
          health_output="$(${healthCheck}/bin/blaziken-health-check)" || health_status=$?
          if [ -n "$health_output" ]; then
            while IFS= read -r line; do
              failures+=("$line")
            done <<< "$health_output"
          elif [ "$health_status" -ne 0 ]; then
            failures+=("blaziken-health-check exited with status $health_status and printed no failure")
          fi

          status=0
          queue="$(postqueue -j)" || status=$?
          if [ "$status" -ne 0 ]; then
            failures+=("postqueue -j failed with exit status $status")
          elif ! stuck="$(jq -rs --argjson cutoff "$(($(date +%s) - 7200))" '
            map(select(.arrival_time < $cutoff)) | sort_by(.arrival_time)
            | if length == 0 then empty
              else "\(length) messages queued over 2h, oldest \(.[0].queue_id) to \(.[0].recipients[0].address)"
              end
          ' <<< "$queue")"; then
            failures+=("postqueue -j returned output jq could not parse")
          elif [ -n "$stuck" ]; then
            failures+=("$stuck")
          fi

          check_blocklist() {
            local address="$1" name="$2" zone="$3" answer
            local -a answers=() refused=() listed=()
            mapfile -t answers < <(dig +short +time=5 +tries=1 @127.0.0.1 "$name" A || true)
            for answer in "''${answers[@]}"; do
              if [[ "$answer" =~ ^127\.255\.255\.[0-9]+$ ]]; then
                refused+=("$answer")
              elif [[ "$answer" =~ ^127\.0\.0\.([0-9]+)$ ]] \
                && [ "$((10#''${BASH_REMATCH[1]}))" -ge 2 ] \
                && [ "$((10#''${BASH_REMATCH[1]}))" -le 254 ]; then
                listed+=("$answer")
              fi
            done
            if [ "''${#refused[@]}" -gt 0 ]; then
              failures+=("$zone refused the query: ''${refused[*]}")
            elif [ "''${#listed[@]}" -gt 0 ]; then
              failures+=("$address listed on $zone: ''${listed[*]}")
            fi
          }
          ${lib.concatMapStrings (
            query:
            "check_blocklist ${
              lib.escapeShellArgs [
                query.address
                query.name
                query.zone
              ]
            }\n"
          ) blocklistQueries}

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
              failures+=("$md mismatch_cnt is $mismatches; run echo repair > /sys/block/$md/md/sync_action, then echo check once it finishes")
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
      options.blaziken.healthCheck = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        default = healthCheck;
        description = "The blaziken-health-check script, shared with blaziken-deploy.";
      };

      config = {
        environment.systemPackages = [ healthCheck ];

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
    };
}
