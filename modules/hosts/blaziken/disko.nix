# KS-5: two HGST HUS724020ALA640 spinning disks. Both disks carry a BIOS boot
# partition and an ESP; the ESPs form a metadata-1.0 raid1 so either disk boots,
# which matters because the KS line has no IPMI to fix a dead boot from.
{ inputs, ... }:
let
  disk = device: {
    type = "disk";
    inherit device;
    content = {
      type = "gpt";
      partitions = {
        mbr = {
          size = "1M";
          type = "EF02";
        };
        esp = {
          size = "1G";
          type = "EF00";
          content = {
            type = "mdraid";
            name = "esp";
          };
        };
        root = {
          size = "100%";
          content = {
            type = "mdraid";
            name = "root";
          };
        };
      };
    };
  };
in
{
  flake.modules.nixos.blaziken = {
    imports = [ inputs.disko.nixosModules.disko ];

    disko.devices = {
      disk = {
        sda = disk "/dev/disk/by-id/ata-HGST_HUS724020ALA640_PN2134P6HDTRJP";
        sdb = disk "/dev/disk/by-id/ata-HGST_HUS724020ALA640_PN1134P6HHXZZN";
      };
      mdadm = {
        esp = {
          type = "mdadm";
          level = 1;
          metadata = "1.0";
          content = {
            type = "filesystem";
            format = "vfat";
            extraArgs = [
              "-n"
              "BLZKN-ESP"
            ];
            mountpoint = "/boot/efi";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          type = "mdadm";
          level = 1;
          content = {
            type = "filesystem";
            format = "ext4";
            extraArgs = [
              "-L"
              "blaziken"
            ];
            mountpoint = "/";
            mountOptions = [ "noatime" ];
          };
        };
      };
    };
  };
}
