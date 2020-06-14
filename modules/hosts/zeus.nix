{config, lib, pkgs, ...}:

{ 
  imports = [
    ../home
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

}
