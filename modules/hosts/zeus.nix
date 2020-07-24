{config, lib, pkgs, ...}:

{ 
  imports = [
    ../zeus
  ];

  boot = {
    loader = {
      # Use the systemd-boot EFI boot loader.
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;

      # Skip the boot selection menu. In order to open it again, repeatedly
      # press the space key on boot
      timeout = 0;
    };

    initrd.luks.devices.luksroot = 
      {
        device = "/dev/nvme0n1p2";
        preLVM = true;
      };
  };

  networking.hostName = "zeus"; # Define host name


  nix.maxJobs = 8;
  nix.buildCores = 8;

  services.xserver = {
    # use open source nvidia drivers
    videoDrivers = [ "nouveau" ];
    libinput = {
      enable = true;
      naturalScrolling = false;
    };
  };

  # connect to local NAS/Share Drive
  fileSystems."/mnt/nas" = {
    device = "//192.168.1.50/Storage";
    fsType = "cifs";
    options = let
      # this line prevents haning on network split
      automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";

    in ["${automount_opts}, credentials=/etc/nixos/smb-secrets"];
  };

}
