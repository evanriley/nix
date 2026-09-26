{
  flake.modules.nixos.boot =
    { lib, pkgs, ... }:
    {
      boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

      # Required for FIDO2 LUKS unlock.
      boot.initrd.systemd.enable = true;

      boot.loader.systemd-boot = {
        enable = true;
        configurationLimit = 20;
      };
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.timeout = 2;

      boot.kernelParams = [
        # zswap in front of zram compresses twice.
        "zswap.enabled=0"
      ];

      services.fwupd.enable = true;
    };
}
