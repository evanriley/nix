{
  flake.modules.nixos.plymouth =
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
      boot.plymouth = {
        enable = true;
        theme = "spinner";
      };
      # NixOS hard-codes DeviceTimeout=8, shorter than the 6K link takes to come up;
      # Plymouth then falls back to text mode.
      boot.initrd.systemd.contents."/etc/plymouth/plymouthd.conf".source = lib.mkForce plymouthConf;
      environment.etc."plymouth/plymouthd.conf".source = lib.mkForce plymouthConf;
      boot.consoleLogLevel = 3;
      boot.initrd.verbose = false;
      boot.kernelParams = [
        "quiet"
        "splash"
        "udev.log_level=3"
      ];
    };
}
