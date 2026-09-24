{ config, ... }:
let
  inherit (config.flake.lib) sessionService mkScript;
in
{
  # Samsung Odyssey G80HS on DP-2. Boot and login are pinned to 6K/165 so
  # Plymouth, GDM and niri share one mode and the screen does not blank.
  # Switch the monitor to 6K before rebooting; display-mode follows the
  # monitor's 3K/330 mode inside niri.
  flake.modules.nixos.cinderace = {
    boot.kernelParams = [
      "video=DP-2:6144x3456@165"
      "plymouth.use-simpledrm=0"
    ];

    environment.etc."xdg/monitors.xml".source = ./monitors.xml;
    systemd.tmpfiles.rules = [
      "d /run/gdm/.config 0711 gdm gdm -"
      "L+ /run/gdm/.config/monitors.xml - - - - ${./monitors.xml}"
    ];
  };

  flake.modules.homeManager.cinderace =
    { lib, pkgs, ... }:
    let
      display-mode = mkScript pkgs {
        name = "display-mode";
        src = ./_scripts/display-mode;
        # steam comes from the system PATH (programs.steam).
        runtimeInputs = [ pkgs.niri ];
      };
    in
    {
      home.file.".local/bin/display-mode".source = lib.getExe display-mode;

      systemd.user.services.display-mode = sessionService {
        description = "Follow the monitor's hardware mode";
        exec = "${lib.getExe display-mode} --watch";
      };
    };
}
