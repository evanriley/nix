{ config, lib, ... }:
let
  cinderace = config.flake.nixosConfigurations.cinderace;
  esp = "15eb8d56-918f-4388-8647-0c4a9a3ad9db";
  luks = "a657bd8b-27fe-4dc7-8d93-520caa984b3c";
in
{
  # Recreates the Arch-era disk (same partition GUIDs and types, LUKS2 with
  # two keyslots, btrfs with the old subvolumes), runs the INSTALL.md phase 7
  # steps, and checks that the partition table and LUKS header are unchanged
  # and the filesystems inside are new.
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.cinderace-disko-adopt =
        let
          scripts =
            (cinderace.extendModules {
              modules = [
                {
                  disko.devices.disk.main.device = lib.mkForce "/dev/vdb";
                  disko.devices.disk.main.content.partitions.luks.content.passwordFile = "/tmp/passphrase";
                }
              ];
            }).config.system.build;
        in
        pkgs.testers.runNixOSTest {
          name = "cinderace-disko-adopt";
          nodes.machine =
            { pkgs, ... }:
            {
              virtualisation.emptyDiskImages = [ 8192 ];
              virtualisation.memorySize = 2048;
              boot.supportedFilesystems = [
                "btrfs"
                "vfat"
              ];
              environment.systemPackages = with pkgs; [
                btrfs-progs
                cryptsetup
                dosfstools
                gptfdisk
              ];
            };
          testScript = ''
            machine.wait_for_unit("multi-user.target")

            def partitions():
                return machine.succeed(
                    "for i in 1 2; do sgdisk -i $i /dev/vdb | grep -v '^Partition name'; done"
                )

            kdf = "--pbkdf pbkdf2 --pbkdf-force-iterations 1000"
            machine.succeed(
                "sgdisk --new=1:2048:+2G --typecode=1:EF00 --partition-guid=1:${esp}"
                " --new=2:0:0 --typecode=2:8300 --partition-guid=2:${luks} /dev/vdb",
                "udevadm settle",
                "echo -n passphrase > /tmp/passphrase",
                "echo -n recovery > /tmp/recovery",
                f"cryptsetup luksFormat -q --type luks2 {kdf} /dev/vdb2 /tmp/passphrase",
                f"cryptsetup luksAddKey -q {kdf} --key-file /tmp/passphrase /dev/vdb2 /tmp/recovery",
                "cryptsetup open --key-file /tmp/passphrase /dev/vdb2 cryptroot",
                "mkfs.btrfs -L arch-root /dev/mapper/cryptroot",
                "mkdir -p /mnt",
                "mount /dev/mapper/cryptroot /mnt",
                "for s in @ @home @snapshots @log @pkg @nix; do btrfs subvolume create /mnt/$s; done",
                "touch /mnt/@/arch-marker",
                "umount /mnt",
                "cryptsetup close cryptroot",
                "mkfs.fat -F 32 -n ARCH_EFI /dev/vdb1",
                "cryptsetup luksHeaderBackup /dev/vdb2 --header-backup-file /tmp/header-before",
            )
            before = partitions()

            with subtest("INSTALL.md 7.3-7.5: unlock, wipe, disko format and mount"):
                machine.succeed(
                    "cryptsetup open --key-file /tmp/passphrase /dev/disk/by-partuuid/${luks} cryptroot",
                    "wipefs -a /dev/mapper/cryptroot",
                    "wipefs -a /dev/disk/by-partuuid/${esp}",
                    "${scripts.formatMount}/bin/disko-format-mount",
                )

            with subtest("partition table unchanged apart from names"):
                after = partitions()
                assert before == after, f"{before}\n!=\n{after}"

            with subtest("LUKS header unchanged, both keys still open it"):
                machine.succeed(
                    "cryptsetup luksHeaderBackup /dev/vdb2 --header-backup-file /tmp/header-after",
                    "cmp /tmp/header-before /tmp/header-after",
                    "cryptsetup open --test-passphrase --key-file /tmp/recovery /dev/vdb2",
                )

            with subtest("new filesystems with the declared layout"):
                subvolumes = machine.succeed(
                    "btrfs subvolume list /mnt | awk '{print $NF}' | sort | tr '\\n' ' '"
                ).strip()
                assert subvolumes == "@ @home @log @nix @snapshots", subvolumes
                machine.fail("test -e /mnt/arch-marker")
                machine.succeed(
                    "test \"$(btrfs filesystem label /mnt)\" = cinderace",
                    "test \"$(blkid -s LABEL -o value /dev/vdb1)\" = BOOT",
                    "findmnt -n -o FSTYPE /mnt/boot | grep -qx vfat",
                    "findmnt /mnt/home/.snapshots",
                    "findmnt /mnt/nix",
                    "findmnt /mnt/var/log",
                )

            with subtest("mount mode reopens and remounts"):
                machine.succeed(
                    "umount -R /mnt",
                    "cryptsetup close cryptroot",
                    "${scripts.mount}/bin/disko-mount",
                    "findmnt /mnt/home",
                    "findmnt /mnt/boot",
                )
          '';
        };
    };
}
