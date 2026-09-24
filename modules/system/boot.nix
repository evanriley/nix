{
  flake.modules.nixos.boot =
    { pkgs, ... }:
    {
      boot.kernelPackages = pkgs.linuxPackages_latest;

      # Required for FIDO2 LUKS unlock.
      boot.initrd.systemd.enable = true;

      boot.loader.systemd-boot = {
        enable = true;
        configurationLimit = 20;
      };
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.timeout = 2;

      boot.plymouth = {
        enable = true;
        theme = "lone";
        themePackages = [
          (pkgs.adi1090x-plymouth-themes.override { selected_themes = [ "lone" ]; })
        ];
      };
      boot.consoleLogLevel = 3;
      boot.initrd.verbose = false;
      boot.kernelParams = [
        "quiet"
        "splash"
        "udev.log_level=3"
        # zswap in front of zram compresses twice.
        "zswap.enabled=0"
      ];

      services.fwupd.enable = true;
    };
}
