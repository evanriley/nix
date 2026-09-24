{
  flake.modules.nixos.boot =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      plymouthConf = pkgs.writeText "plymouthd.conf" ''
        [Daemon]
        ShowDelay=${toString config.boot.plymouth.showDelay}
        DeviceTimeout=30
        Theme=${config.boot.plymouth.theme}
      '';
    in
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
        theme = "spinner";
      };
      # NixOS hard-codes DeviceTimeout=8. amdgpu registers its display 8-13 s after
      # Plymouth starts (6K link), so Plymouth fell back to text mode.
      boot.initrd.systemd.contents."/etc/plymouth/plymouthd.conf".source = lib.mkForce plymouthConf;
      environment.etc."plymouth/plymouthd.conf".source = lib.mkForce plymouthConf;
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
