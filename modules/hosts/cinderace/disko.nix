{ inputs, ... }:
{
  flake.modules.nixos.cinderace = {
    imports = [ inputs.disko.nixosModules.disko ];

    # Partition UUIDs and types match the existing disk. disko adopts existing
    # partitions and an existing LUKS container instead of recreating them, so
    # the LUKS header (passphrase, recovery key, FIDO2 enrollments) survives a
    # reinstall. Checked by checks.x86_64-linux.cinderace-disko-adopt.
    disko.devices.disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-Samsung_SSD_9100_PRO_2TB_S7YCNJ0Y201797K";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            uuid = "15eb8d56-918f-4388-8647-0c4a9a3ad9db";
            size = "2G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              extraArgs = [
                "-n"
                "BOOT"
              ];
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          luks = {
            uuid = "a657bd8b-27fe-4dc7-8d93-520caa984b3c";
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              settings = {
                allowDiscards = true;
                crypttabExtraOpts = [ "fido2-device=auto" ];
              };
              content = {
                type = "btrfs";
                extraArgs = [
                  "-L"
                  "cinderace"
                ];
                subvolumes =
                  let
                    mountOptions = [
                      "compress=zstd:3"
                      "noatime"
                    ];
                  in
                  {
                    "@" = {
                      mountpoint = "/";
                      inherit mountOptions;
                    };
                    "@home" = {
                      mountpoint = "/home";
                      inherit mountOptions;
                    };
                    "@snapshots" = {
                      mountpoint = "/home/.snapshots";
                      inherit mountOptions;
                    };
                    "@nix" = {
                      mountpoint = "/nix";
                      inherit mountOptions;
                    };
                    "@log" = {
                      mountpoint = "/var/log";
                      inherit mountOptions;
                    };
                  };
              };
            };
          };
        };
      };
    };

    fileSystems."/var/log".neededForBoot = true;
  };
}
