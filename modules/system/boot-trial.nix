{
  flake.modules.nixos.boot-trial =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.bootTrial;

      systemProfile = "/nix/var/nix/profiles/system";
      lastGoodProfile = "/nix/var/nix/profiles/system-profiles/lastgood";
      lastGoodSubmenu = "NixOS - Profile 'lastgood'";
      grubEnv = "/boot/grub/grubenv";
      attempted = "${cfg.stateDirectory}/boot-attempted";
      trialMarker = "boot_trial=1";
      healthyMarker = "/run/boot-trial-healthy";
      # switch-to-configuration starts inactive wanted units, so without this marker the failing unit reruns during the redeploy's switch, which then exits 4 and rolls back
      checkedMarker = "/run/boot-trial-fallback-checked";
      stopOnReboot = "watchdog.stop_on_reboot=0";
      microseconds = seconds: toString (seconds * 1000000);

      requireConfirmed = ''
        if grep -qE '(^| )${trialMarker}( |$)' /proc/cmdline && [ ! -e ${healthyMarker} ]; then
          echo "This boot is a kernel trial that has not passed its health check; expected a confirmed boot. Wait for boot-trial-confirm.service (systemctl status boot-trial-confirm), then run $(basename "$0") again" >&2
          exit 1
        fi
      '';

      identity = pkgs.writeShellApplication {
        name = "boot-identity";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          if [ "$#" -ne 1 ]; then
            echo "usage: boot-identity <system>" >&2
            exit 2
          fi
          for file in kernel initrd kernel-modules kernel-params; do
            if [ ! -e "$1/$file" ]; then
              echo "$1/$file does not exist, expected a NixOS system closure such as the output of nix build ...#nixosConfigurations.<host>.config.system.build.toplevel" >&2
              exit 1
            fi
          done
          printf '%s %s %s %s\n' \
            "$(readlink -f "$1/kernel")" \
            "$(readlink -f "$1/initrd")" \
            "$(readlink -f "$1/kernel-modules")" \
            "$(cat "$1/kernel-params")"
        '';
      };

      entry = pkgs.writeShellApplication {
        name = "boot-entry";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gawk
          pkgs.gnugrep
        ];
        text = ''
          if [ "$#" -ne 2 ]; then
            echo "usage: boot-entry <system> <submenu title>" >&2
            exit 2
          fi
          init=$(readlink -f "$1/init")
          entries=$(awk -v init="init=$init" -v submenu="$2" '
            function title(line) {
              match(line, /"[^"]*"/)
              return substr(line, RSTART + 1, RLENGTH - 2)
            }
            /^[[:space:]]*submenu "/ { depth++; name[depth] = title($0); next }
            /^[[:space:]]*menuentry "/ { depth++; name[depth] = title($0); next }
            /^[[:space:]]*function / { depth++; name[depth] = ""; next }
            /^[[:space:]]*}/ { depth--; next }
            /^[[:space:]]*linux / {
              for (i = 1; i <= NF; i++) if ($i == init) {
                path = name[1]
                for (j = 2; j <= depth; j++) path = path ">" name[j]
                if (index(path, submenu ">") == 1) print path
              }
            }
          ' /boot/grub/grub.cfg)
          count=$(printf '%s' "$entries" | grep -c . || true)
          if [ "$count" -ne 1 ]; then
            echo "Found $count GRUB entries for $init under '$2' in /boot/grub/grub.cfg; expected exactly 1. Run switch-to-configuration boot to regenerate the menu" >&2
            exit 1
          fi
          printf '%s\n' "$entries"
        '';
      };

      pin = pkgs.writeShellApplication {
        name = "boot-trial-pin";
        runtimeInputs = [
          identity
          entry
          config.system.build.grub
          config.nix.package
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gnused
        ];
        text = ''
          ${requireConfirmed}
          booted=$(readlink -f /run/booted-system)
          running=$(readlink -f /run/current-system)
          if [ "$(boot-identity "$running")" = "$(boot-identity "$booted")" ]; then
            system=$running
          else
            system=$booted
          fi
          pinned=$(readlink -f ${lastGoodProfile} 2> /dev/null || true)
          if [ "$pinned" = "$system" ]; then
            current=$(boot-entry "$system" "${lastGoodSubmenu}" 2> /dev/null || true)
            saved=$({ grub-editenv ${grubEnv} list 2> /dev/null || true; } | sed -n 's/^saved_entry=//p')
            if [ -n "$current" ] && [ "$saved" = "$current" ]; then
              echo "$system is already the pinned last-good system"
              exit 0
            fi
          else
            mkdir -p "$(dirname ${lastGoodProfile})"
            nix-env -p ${lastGoodProfile} --set "$system"
            nix-env -p ${lastGoodProfile} --delete-generations +2
          fi
          ${systemProfile}/bin/switch-to-configuration boot
          pinned_entry=$(boot-entry "$system" "${lastGoodSubmenu}")
          grub-editenv ${grubEnv} set "saved_entry=$pinned_entry"
          grub-editenv ${grubEnv} unset next_entry
          sync ${grubEnv}
          echo "pinned $system: saved_entry=$pinned_entry"
        '';
      };

      start = pkgs.writeShellApplication {
        name = "boot-trial-start";
        runtimeInputs = [
          identity
          pin
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.kexec-tools
          config.systemd.package
        ];
        text = ''
          if [ "$#" -ne 1 ]; then
            echo "usage: boot-trial-start <system>" >&2
            exit 2
          fi
          ${requireConfirmed}
          candidate=$(readlink -f "$1")
          profile_target=$(readlink -f ${systemProfile})
          if [ "$candidate" != "$profile_target" ]; then
            echo "${systemProfile} points at $profile_target, expected $candidate; the fallback check compares against the profile. Run nix-env -p ${systemProfile} --set $candidate, then boot-trial-start again" >&2
            exit 1
          fi
          booted=$(readlink -f /run/booted-system)
          candidate_identity=$(boot-identity "$candidate")
          kernel=$(readlink -f "$candidate/kernel")
          if [ "$(boot-identity "$booted")" = "$candidate_identity" ]; then
            echo "booted kernel, initrd, modules and parameters match $candidate; no trial needed"
            exit 0
          fi
          mkdir -p ${cfg.stateDirectory}
          if grep -qxF -- "$candidate_identity" ${attempted} 2> /dev/null; then
            echo "already attempted $kernel; not retrying. Remove its line from ${attempted} to retry"
            exit 0
          fi
          unarmed=()
          if ! grep -qE '(^| )${stopOnReboot}( |$)' /proc/cmdline; then
            unarmed+=("the running kernel's /proc/cmdline lacks ${stopOnReboot}, so it stops the hardware watchdog when systemd closes it; reboot into a system that has it")
          fi
          if ! grep -qE '(^| )${stopOnReboot}( |$)' "$candidate/kernel-params"; then
            unarmed+=("$candidate/kernel-params lacks ${stopOnReboot}; import nixos.boot-trial in that system")
          fi
          if [ ! -e "$candidate/etc/systemd/system/boot-trial-confirm.service" ]; then
            unarmed+=("$candidate has no boot-trial-confirm.service, so its trial boot cannot confirm itself; import nixos.boot-trial in that system")
          fi
          kexec_watchdog=$(busctl get-property org.freedesktop.systemd1 /org/freedesktop/systemd1 \
            org.freedesktop.systemd1.Manager KExecWatchdogUSec 2>&1 || true)
          if [ "$kexec_watchdog" != "t ${microseconds cfg.trialSeconds}" ]; then
            unarmed+=("systemd's KExecWatchdogUSec is '$kexec_watchdog', expected 't ${microseconds cfg.trialSeconds}'; the running systemd was started from a system.conf without KExecWatchdogSec=${toString cfg.trialSeconds}s")
          fi
          watchdog_state=$(cat /sys/class/watchdog/${cfg.watchdogDevice}/state 2>&1 || true)
          if [ "$watchdog_state" != active ]; then
            unarmed+=("/sys/class/watchdog/${cfg.watchdogDevice}/state is '$watchdog_state', expected 'active'; systemd must hold the watchdog open through RuntimeWatchdogSec")
          fi
          if [ "''${#unarmed[@]}" -gt 0 ]; then
            echo "refusing to trial $kernel: the hardware watchdog would not be armed across the kexec; nothing was recorded in ${attempted}" >&2
            printf -- '- %s\n' "''${unarmed[@]}" >&2
            exit 1
          fi
          boot-trial-pin
          kexec --load "$candidate/kernel" --initrd="$candidate/initrd" \
            --append="init=$candidate/init $(cat "$candidate/kernel-params") ${lib.concatStringsSep " " trialKernelParams}"
          if [ "$(cat /sys/kernel/kexec_loaded)" != 1 ]; then
            echo "kexec --load of $kernel finished but /sys/kernel/kexec_loaded is not 1; expected a loaded kernel. Check dmesg" >&2
            exit 1
          fi
          printf '%s\n' "$candidate_identity" >> ${attempted}
          sync ${attempted}
          echo "trying $kernel by kexec"
          systemctl kexec
        '';
      };

      fallback = pkgs.writeShellApplication {
        name = "boot-trial-fallback";
        runtimeInputs = [
          identity
          pkgs.coreutils
        ];
        text = ''
          if [ ! -s ${attempted} ]; then
            exit 0
          fi
          newest=$(tail -n 1 ${attempted})
          booted_identity=$(boot-identity /run/booted-system)
          profile_identity=$(boot-identity ${systemProfile})
          if [ "$newest" = "$booted_identity" ] || [ "$newest" != "$profile_identity" ]; then
            exit 0
          fi
          echo "fell back from ''${newest%% *} to $(readlink -f /run/booted-system/kernel); remove its line from ${attempted} to retry" >&2
          exit 1
        '';
      };

      confirm = pkgs.writeShellApplication {
        name = "boot-trial-confirm";
        runtimeInputs = [
          pin
          pkgs.coreutils
          config.systemd.package
        ];
        text = ''
          deadline=$((SECONDS + ${toString cfg.healthCheckTimeoutSeconds}))
          until failures=$(${lib.getExe cfg.healthCheck} 2>&1); do
            if [ "$SECONDS" -ge "$deadline" ]; then
              echo "health check still failing after ${toString cfg.healthCheckTimeoutSeconds} s; expected it to pass on the trial kernel $(readlink -f /run/booted-system/kernel):" >&2
              printf '%s\n' "$failures" >&2
              echo "rebooting into the pinned last-good entry" >&2
              systemctl reboot
              exit 1
            fi
            sleep ${toString cfg.healthCheckIntervalSeconds}
          done
          touch ${healthyMarker}
          pin_status=0
          boot-trial-pin || pin_status=$?
          for property in \
            RuntimeWatchdogUSec=${microseconds cfg.runtimeWatchdogSeconds} \
            RebootWatchdogUSec=${microseconds cfg.rebootWatchdogSeconds} \
            KExecWatchdogUSec=${microseconds cfg.trialSeconds}; do
            busctl set-property org.freedesktop.systemd1 /org/freedesktop/systemd1 \
              org.freedesktop.systemd1.Manager "''${property%%=*}" t "''${property#*=}"
          done
          echo "boot confirmed: $(readlink -f /run/booted-system)"
          exit "$pin_status"
        '';
      };

      trialKernelParams = [
        trialMarker
        "systemd.watchdog_sec=0"
        "watchdog.handle_boot_enabled=0"
        "${cfg.heartbeatParameter}=${toString cfg.trialSeconds}"
      ];
    in
    {
      options.bootTrial = {
        healthCheck = lib.mkOption {
          type = lib.types.package;
          description = "Program that prints one failure per line and exits 1 when the system is unhealthy; run on a trial boot until it passes.";
        };
        healthCheckTimeoutSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 300;
          description = "How long a trial boot may take to pass the health check before it reboots into the last-good entry.";
        };
        healthCheckIntervalSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 30;
        };
        trialSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          description = "Hardware watchdog timeout armed across the kexec; the trial kernel must boot and pass the health check within it.";
        };
        heartbeatParameter = lib.mkOption {
          type = lib.types.str;
          example = "intel_oc_wdt.heartbeat";
          description = "Kernel parameter that sets the hardware watchdog driver's timeout in seconds.";
        };
        watchdogDevice = lib.mkOption {
          type = lib.types.str;
          default = "watchdog0";
          description = "Device under /sys/class/watchdog that systemd's KExecWatchdogSec arms; it must be active before a trial starts.";
        };
        runtimeWatchdogSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 60;
        };
        rebootWatchdogSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 600;
        };
        stateDirectory = lib.mkOption {
          type = lib.types.path;
          description = "Directory that holds boot-attempted, the boot identities already trialled.";
        };
        redeployUnit = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Unit started when a boot fell back from a failed trial.";
        };
        commands = lib.mkOption {
          type = lib.types.attrsOf lib.types.package;
          readOnly = true;
          default = {
            inherit
              identity
              entry
              pin
              start
              fallback
              ;
          };
          description = "The boot-identity, boot-entry, boot-trial-pin, boot-trial-start and boot-trial-fallback commands.";
        };
      };

      config = {
        assertions = [
          {
            assertion = cfg.trialSeconds > cfg.healthCheckTimeoutSeconds;
            message = "bootTrial.trialSeconds (${toString cfg.trialSeconds}) must exceed bootTrial.healthCheckTimeoutSeconds (${toString cfg.healthCheckTimeoutSeconds}), or the watchdog resets a trial that is still being checked";
          }
        ];

        boot.loader.grub.default = "\"\${saved_entry}\"";
        boot.kernelParams = [ stopOnReboot ];

        systemd.settings.Manager = {
          RuntimeWatchdogSec = "${toString cfg.runtimeWatchdogSeconds}s";
          RebootWatchdogSec = "${toString cfg.rebootWatchdogSeconds}s";
          KExecWatchdogSec = "${toString cfg.trialSeconds}s";
        };

        environment.systemPackages = lib.attrValues cfg.commands;

        systemd.services.boot-trial-confirm = {
          description = "Confirm a healthy kernel trial and pin it as the last-good system";
          wantedBy = [ "multi-user.target" ];
          after = [ "multi-user.target" ];
          restartIfChanged = false;
          unitConfig.ConditionKernelCommandLine = trialMarker;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe confirm;
          };
        };

        systemd.services.boot-trial-fallback = {
          description = "Fail when this boot fell back from a failed kernel trial";
          wantedBy = [ "multi-user.target" ];
          after = [ "multi-user.target" ];
          restartIfChanged = false;
          onFailure = lib.optional (cfg.redeployUnit != null) cfg.redeployUnit;
          unitConfig = {
            ConditionKernelCommandLine = "!${trialMarker}";
            ConditionPathExists = "!${checkedMarker}";
          };
          serviceConfig = {
            Type = "oneshot";
            ExecStartPre = "${pkgs.coreutils}/bin/touch ${checkedMarker}";
            ExecStart = lib.getExe fallback;
          };
        };
      };
    };
}
