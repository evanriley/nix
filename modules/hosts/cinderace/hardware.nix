{
  flake.modules.nixos.cinderace =
    { modulesPath, ... }:
    let
      ext4 = uuid: {
        device = "/dev/disk/by-uuid/${uuid}";
        fsType = "ext4";
        options = [
          "noatime"
          "nofail"
          "nosuid"
          "nodev"
        ];
      };
    in
    {
      imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

      nixpkgs.hostPlatform = "x86_64-linux";

      hardware.cpu.amd.updateMicrocode = true;
      hardware.enableRedistributableFirmware = true;
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };
      # Plymouth needs amdgpu in the initrd to draw at the panel's native mode.
      hardware.amdgpu.initrd.enable = true;

      boot.initrd.availableKernelModules = [
        "nvme"
        "xhci_pci"
        "thunderbolt"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
      boot.kernelModules = [ "kvm-amd" ];

      fileSystems = {
        "/mnt/Media" = ext4 "79cdba09-88c5-4f14-901b-11731d773abe";
        "/mnt/Games" = ext4 "eaf05b17-caee-4b76-8754-9ffe20d4e0fb";
        # Lidarr's database and slskd's settings store paths under /data.
        "/data" = {
          device = "/mnt/Media";
          fsType = "none";
          options = [
            "bind"
            "nofail"
            "x-systemd.requires-mounts-for=/mnt/Media"
          ];
        };
      };

      zramSwap = {
        enable = true;
        algorithm = "zstd";
        memoryPercent = 50;
        memoryMax = 16 * 1024 * 1024 * 1024;
        priority = 100;
      };
    };
}
