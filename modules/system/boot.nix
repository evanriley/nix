{
  flake.modules.nixos.boot =
    { lib, pkgs, ... }:
    {
      boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

      boot.loader.systemd-boot = {
        enable = true;
        configurationLimit = 20;
      };
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.timeout = 2;

      services.fwupd.enable = true;
    };
}
