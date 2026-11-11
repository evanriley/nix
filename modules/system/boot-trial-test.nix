{ config, inputs, ... }:
let
  nixos = config.flake.modules.nixos;
  inherit (inputs.nixpkgs) lib;
in
{
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      packages.blaziken-boot-trial-test =
        let
          disks = [
            "/dev/disk/by-id/virtio-diskA"
            "/dev/disk/by-id/virtio-diskB"
          ];
          trialSeconds = 90;

          hangUnit = sleep: {
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${sleep} infinity";
              TimeoutStartSec = "infinity";
            };
          };

          targetModule =
            variant:
            { modulesPath, ... }:
            {
              imports = [
                "${modulesPath}/testing/test-instrumentation.nix"
                "${modulesPath}/profiles/qemu-guest.nix"
              ]
              ++ lib.optional (variant != "no-module") nixos.boot-trial;

              config = lib.mkMerge [
                {
                  system.stateVersion = "26.05";
                  networking.hostName = "target";
                  documentation.enable = false;
                  nix.package = pkgs.lix;

                  systemd.services.target-redeploy = {
                    serviceConfig = {
                      Type = "oneshot";
                      ExecStart = "${pkgs.coreutils}/bin/touch /run/target-redeployed";
                    };
                  };

                  boot.loader.grub = {
                    enable = true;
                    efiSupport = true;
                    efiInstallAsRemovable = true;
                    devices = disks;
                    configurationLimit = 2;
                    extraConfig = "serial; terminal_input serial; terminal_output serial";
                  };
                  boot.loader.efi = {
                    canTouchEfiVariables = false;
                    efiSysMountPoint = "/boot/efi";
                  };
                  boot.loader.timeout = 2;

                  boot.kernelParams = [
                    "panic=5"
                    "boot.variant=${if variant == "good2-userspace" then "good2" else variant}"
                    "i6300esb.nowayout=1"
                  ];

                  boot.swraid = {
                    enable = true;
                    mdadmConf = "PROGRAM ${pkgs.coreutils}/bin/true";
                  };
                  fileSystems."/" = {
                    device = "/dev/md/root";
                    fsType = "ext4";
                    options = [ "noatime" ];
                  };
                  fileSystems."/boot/efi" = {
                    device = "/dev/md/esp";
                    fsType = "vfat";
                    options = [ "umask=0077" ];
                  };

                  environment.systemPackages = [ pkgs.util-linux ];
                }

                (lib.optionalAttrs (variant != "no-module") {
                  bootTrial = {
                    healthCheck = pkgs.writeShellApplication {
                      name = "target-health-check";
                      text = ''
                        if grep -q boot.variant=unhealthy /proc/cmdline; then
                          echo "failed unit: unhealthy.service"
                          exit 1
                        fi
                      '';
                    };
                    healthCheckTimeoutSeconds = 20;
                    healthCheckIntervalSeconds = 5;
                    inherit trialSeconds;
                    heartbeatParameter = "i6300esb.heartbeat";
                    runtimeWatchdogSeconds = 30;
                    rebootWatchdogSeconds = 300;
                    stateDirectory = "/var/lib/boot-trial";
                    redeployUnit = "target-redeploy.service";
                  };
                })

                (lib.mkIf (variant == "good2-userspace") { environment.etc.boot-trial-variant.text = variant; })

                (lib.mkIf (variant == "panic") { boot.kernelParams = [ "rdinit=/does-not-exist" ]; })

                (lib.mkIf (variant == "initrd-hang") {
                  boot.initrd.systemd.services.hang = hangUnit "/bin/sleep" // {
                    wantedBy = [ "initrd.target" ];
                    before = [ "initrd-root-fs.target" ];
                    unitConfig.DefaultDependencies = false;
                  };
                  boot.initrd.systemd.targets.initrd-root-fs.requires = [ "hang.service" ];
                })

                (lib.mkIf (variant == "stage2-hang") {
                  systemd.services.hang = hangUnit "${pkgs.coreutils}/bin/sleep" // {
                    wantedBy = [ "multi-user.target" ];
                    before = [ "multi-user.target" ];
                  };
                })
              ];
            };

          systems =
            lib.genAttrs
              [
                "good"
                "good2"
                "good2-userspace"
                "panic"
                "stage2-hang"
                "initrd-hang"
                "unhealthy"
                "no-module"
              ]
              (
                variant:
                (inputs.nixpkgs.lib.nixosSystem {
                  modules = [
                    { nixpkgs.hostPlatform = system; }
                    (targetModule variant)
                  ];
                }).config.system.build.toplevel
              );

          diskNodes = [
            {
              size = 6144;
              driveConfig.deviceExtraOpts.serial = "diskA";
            }
            {
              size = 6144;
              driveConfig.deviceExtraOpts.serial = "diskB";
            }
          ];

          install = pkgs.writeShellApplication {
            name = "install-target";
            runtimeInputs = with pkgs; [
              gptfdisk
              mdadm
              dosfstools
              e2fsprogs
              util-linux
              systemd
              nix
              nixos-install-tools
            ];
            text = ''
              mkdir -p /mnt
              for disk in /dev/disk/by-id/virtio-diskA /dev/disk/by-id/virtio-diskB; do
                sgdisk -Z -n1:0:+1M -t1:EF02 -n2:0:+256M -t2:EF00 -n3:0:0 -t3:FD00 "$disk"
              done
              udevadm settle
              mdadm --create /dev/md/esp --run --level=1 --raid-devices=2 --metadata=1.0 \
                --homehost=any --name=esp /dev/disk/by-id/virtio-diskA-part2 /dev/disk/by-id/virtio-diskB-part2
              mdadm --create /dev/md/root --run --level=1 --raid-devices=2 --metadata=1.2 \
                --homehost=any --name=root /dev/disk/by-id/virtio-diskA-part3 /dev/disk/by-id/virtio-diskB-part3
              udevadm settle
              mkfs.vfat -n ESP /dev/md/esp
              mkfs.ext4 -q -L root /dev/md/root
              mount /dev/md/root /mnt
              mkdir -p /mnt/boot/efi
              mount /dev/md/esp /mnt/boot/efi
              nixos-install --root /mnt --system ${systems.good} --no-root-passwd --no-channel-copy
              nix --extra-experimental-features nix-command copy --no-check-sigs --to /mnt \
                ${lib.concatStringsSep " " (lib.attrValues systems)}
              umount -R /mnt
              mdadm --wait /dev/md/esp /dev/md/root || true
              sync
            '';
          };
        in
        pkgs.testers.runNixOSTest {
          name = "blaziken-boot-trial";
          globalTimeout = 3600;
          nodes = {
            installer = {
              virtualisation.emptyDiskImages = diskNodes;
              virtualisation.memorySize = 2048;
              virtualisation.additionalPaths = lib.attrValues systems;
              boot.swraid = {
                enable = true;
                mdadmConf = "PROGRAM ${pkgs.coreutils}/bin/true";
              };
              nix.settings.substituters = lib.mkForce [ ];
              environment.systemPackages = [ install ];
            };
            target = {
              virtualisation.emptyDiskImages = diskNodes;
              virtualisation.memorySize = 2048;
              virtualisation.diskImage = null;
              virtualisation.useBootLoader = true;
              virtualisation.useEFIBoot = true;
              virtualisation.useDefaultFilesystems = false;
              virtualisation.efi.keepVariables = false;
              virtualisation.fileSystems."/" = {
                device = "/dev/disk/by-label/unused";
                fsType = "ext4";
              };
              virtualisation.qemu.options = [ "-device i6300esb" ];
            };
          };
          testScript = ''
            import datetime
            import re
            import time

            good = "${systems.good}"
            good2 = "${systems.good2}"
            good2_userspace = "${systems.good2-userspace}"
            panic = "${systems.panic}"
            stage2_hang = "${systems.stage2-hang}"
            initrd_hang = "${systems.initrd-hang}"
            unhealthy = "${systems.unhealthy}"
            no_module = "${systems.no-module}"
            trial_seconds = ${toString trialSeconds}
            lastgood_submenu = "NixOS - Profile 'lastgood'>"
            attempted = "/var/lib/boot-trial/boot-attempted"

            def secs(n):
                return datetime.timedelta(seconds=n)

            def show(cmd):
                out = target.succeed(cmd)
                print(f"$ {cmd}\n{out}")
                return out

            def booted():
                return target.succeed("readlink -f /run/booted-system").strip()

            def console_lines(pattern):
                return [l for l in target.get_console_log().splitlines() if re.search(pattern, l)]

            def saved_entry():
                return target.succeed("grub-editenv /boot/grub/grubenv list | sed -n 's/^saved_entry=//p'").strip()

            def lastgood():
                return target.succeed("readlink -f /nix/var/nix/profiles/system-profiles/lastgood").strip()

            def unit_state(unit):
                return target.succeed(f"systemctl show -p ActiveState,Result --value {unit}").split()

            def normal_boot(expected):
                target.connected = False
                target.wait_for_unit("multi-user.target", timeout=secs(900))
                target.succeed("systemctl is-system-running --wait || true")
                assert booted() == expected, booted()
                target.fail("grep -q boot_trial=1 /proc/cmdline")

            def trial_boot(expected):
                target.connected = False
                target.wait_for_unit("boot-trial-confirm.service", timeout=secs(900))
                assert booted() == expected, booted()
                target.succeed("grep -q boot_trial=1 /proc/cmdline")

            def start_trial(system):
                target.succeed(f"nix-env -p /nix/var/nix/profiles/system --set {system}")
                target.execute(
                    "systemd-run --unit=boot-trial-run -p StandardOutput=journal+console "
                    "/run/current-system/sw/bin/boot-trial-start " + system
                )
                target.connected = False
                target.wait_for_console_text("trying /nix/store/.* by kexec", timeout=secs(300))
                return time.monotonic()

            def wait_reset(started, limit):
                target.wait_for_console_text("GNU GRUB  version", timeout=secs(limit))
                elapsed = time.monotonic() - started
                print(f"firmware reset reached GRUB {elapsed:.0f} s after the kexec started")
                return elapsed

            def assert_fell_back(expected_attempts):
                assert unit_state("boot-trial-fallback.service") == ["failed", "exit-code"], unit_state("boot-trial-fallback.service")
                show("journalctl -b -u boot-trial-fallback.service --no-pager | grep 'fell back from'")
                target.succeed("test -e /run/target-redeployed")
                assert saved_entry().startswith(lastgood_submenu), saved_entry()
                assert lastgood() == good, lastgood()
                assert len(target.succeed(f"cat {attempted}").splitlines()) == expected_attempts

            def assert_not_retried(system):
                out = show(f"boot-trial-start {system}")
                assert "already attempted" in out, out
                assert booted() == good

            installer.start()
            installer.succeed("install-target >&2", timeout=secs(1800))
            installer.shutdown()

            target.state_dir = installer.state_dir
            target.start(allow_reboot=True)

            with subtest("first boot is unpinned and pinning is idempotent"):
                target.wait_for_unit("multi-user.target", timeout=secs(900))
                target.succeed("systemctl is-system-running --wait || true")
                assert booted() == good
                assert saved_entry() == ""
                assert unit_state("boot-trial-fallback.service")[0] == "inactive"
                cmdline = show("cat /proc/cmdline")
                assert "watchdog.stop_on_reboot=0" in cmdline
                show("grep -c 'saved_entry' /boot/grub/grub.cfg")
                show("boot-trial-pin")
                assert saved_entry().startswith(lastgood_submenu), saved_entry()
                assert lastgood() == good
                assert "already the pinned" in show("boot-trial-pin")
                assert target.succeed("ls /nix/var/nix/profiles/system-profiles/ | grep -c 'lastgood-.*-link'").strip() == "1"
                assert "no trial needed" in show(f"boot-trial-start {good}")

            with subtest("panicking kernel falls back to the pinned entry and is not retried"):
                started = start_trial(panic)
                target.wait_for_console_text("Kernel panic", timeout=secs(300))
                wait_reset(started, 120)
                normal_boot(good)
                assert_fell_back(1)
                assert_not_retried(panic)
                show("boot-trial-fallback || true")
                target.fail("boot-trial-fallback")
                show("/nix/var/nix/profiles/system/bin/switch-to-configuration switch")
                assert unit_state("boot-trial-fallback.service")[0] == "inactive"
                assert_not_retried(panic)

            with subtest("stage 2 hang is reset by the watchdog and refuses to pin before confirmation"):
                started = start_trial(stage2_hang)
                target.succeed("true")
                target.succeed("grep -q boot_trial=1 /proc/cmdline")
                for cmd in ["boot-trial-pin", f"boot-trial-start {good}"]:
                    out = target.fail(f"{cmd} 2>&1 | tee /dev/stderr; exit 1")
                target.fail("boot-trial-pin")
                target.connected = False
                elapsed = wait_reset(started, 300)
                assert elapsed < trial_seconds + 60, elapsed
                normal_boot(good)
                assert_fell_back(2)
                assert_not_retried(stage2_hang)

            with subtest("initrd hang is reset by the watchdog"):
                started = start_trial(initrd_hang)
                elapsed = wait_reset(started, 300)
                assert elapsed < trial_seconds + 60, elapsed
                normal_boot(good)
                assert_fell_back(3)
                assert_not_retried(initrd_hang)

            with subtest("failing health check reboots before the watchdog expires"):
                started = start_trial(unhealthy)
                target.connect()
                target.wait_for_console_text("rebooting into the pinned last-good entry", timeout=secs(300))
                elapsed = wait_reset(started, 300)
                assert elapsed < trial_seconds - 5, elapsed
                normal_boot(good)
                assert_fell_back(4)
                assert_not_retried(unhealthy)
                show("journalctl -b -1 -u boot-trial-confirm.service --no-pager | tail -n 8")

            with subtest("healthy trial is pinned and survives a firmware reboot"):
                start_trial(good2)
                trial_boot(good2)
                target.succeed("test -e /run/boot-trial-healthy")
                assert saved_entry().startswith(lastgood_submenu), saved_entry()
                assert lastgood() == good2
                assert unit_state("boot-trial-fallback.service")[0] == "inactive"
                target.succeed("boot-trial-fallback")
                for prop, usec in [("RuntimeWatchdogUSec", 30000000), ("RebootWatchdogUSec", 300000000), ("KExecWatchdogUSec", trial_seconds * 1000000)]:
                    got = target.succeed(f"busctl get-property org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager {prop}").strip()
                    assert got == f"t {usec}", (prop, got)
                assert len(target.succeed(f"cat {attempted}").splitlines()) == 5
                show("grub-editenv /boot/grub/grubenv list")
                show("ls -l /nix/var/nix/profiles/system-profiles/")
                show("grep -nE '^ *(submenu|menuentry)' /boot/grub/grub.cfg")
                entry_after_trial = saved_entry()
                target.reboot()
                normal_boot(good2)
                assert saved_entry() == entry_after_trial
                assert lastgood() == good2
                assert unit_state("boot-trial-fallback.service")[0] == "inactive"
                target.succeed("boot-trial-fallback")
                assert "no trial needed" in show(f"boot-trial-start {good2}")
                assert "already the pinned" in show("boot-trial-pin")

            with subtest("a switch that keeps the kernel pins the running system"):
                target.succeed(f"nix-env -p /nix/var/nix/profiles/system --set {good2_userspace}")
                show(f"{good2_userspace}/bin/switch-to-configuration switch")
                assert "no trial needed" in show(f"boot-trial-start {good2_userspace}")
                show("boot-trial-pin")
                assert lastgood() == good2_userspace, lastgood()
                assert saved_entry().startswith(lastgood_submenu), saved_entry()
                target.succeed("boot-trial-fallback")
                target.reboot()
                normal_boot(good2_userspace)
                assert lastgood() == good2_userspace
                assert unit_state("boot-trial-fallback.service")[0] == "inactive"
                assert "already the pinned" in show("boot-trial-pin")

            with subtest("a trial without the armed watchdog is refused and not recorded"):
                attempted_before = target.succeed(f"cat {attempted}")
                saved_before = saved_entry()
                lastgood_before = lastgood()
                target.succeed(f"nix-env -p /nix/var/nix/profiles/system --set {no_module}")
                show(f"{no_module}/bin/switch-to-configuration switch")
                show("busctl get-property org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager KExecWatchdogUSec")
                show("cat /sys/class/watchdog/watchdog0/state")
                refuse = f"{good2_userspace}/sw/bin/boot-trial-start {no_module}"

                def assert_refused_untouched():
                    assert target.succeed(f"cat {attempted}") == attempted_before
                    assert saved_entry() == saved_before, saved_entry()
                    assert lastgood() == lastgood_before, lastgood()
                    assert target.succeed("cat /sys/kernel/kexec_loaded").strip() == "0"

                status, out = target.execute(f"{refuse} 2>&1")
                print(f"$ {refuse}\n{out}")
                assert status == 1, status
                assert "refusing to trial" in out and "nothing was recorded" in out, out
                assert "has no boot-trial-confirm.service" in out, out
                assert f"{no_module}/kernel-params lacks watchdog.stop_on_reboot=0" in out, out
                assert "KExecWatchdogUSec is" in out, out
                assert "running kernel's /proc/cmdline lacks" not in out, out
                assert_refused_untouched()

                target.succeed("sed 's/watchdog.stop_on_reboot=0//' /proc/cmdline > /run/cmdline-without-stop-on-reboot")
                target.succeed("mount --bind /run/cmdline-without-stop-on-reboot /proc/cmdline")
                try:
                    status, out = target.execute(f"{refuse} 2>&1")
                    print(f"$ {refuse}  (with /proc/cmdline lacking the parameter)\n{out}")
                finally:
                    target.succeed("umount /proc/cmdline")
                assert status == 1, status
                assert "running kernel's /proc/cmdline lacks watchdog.stop_on_reboot=0" in out, out
                assert_refused_untouched()
                assert "watchdog.stop_on_reboot=0" in target.succeed("cat /proc/cmdline")

            print("\n".join(console_lines("trying /nix/store|Kernel panic - not syncing|health check still failing|rebooting into|GNU GRUB  version|pinned /nix/store|boot confirmed|fell back from")))
          '';
        };
    };
}
