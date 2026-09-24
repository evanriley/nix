{ config, ... }:
let
  inherit (config.meta) user;
  inherit (config.flake.lib) sessionService;
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

    home-manager.users.${user.name} =
      { config, ... }:
      {
        dotfiles.bin = [ "display-mode" ];

        systemd.user.services.display-mode = sessionService {
          description = "Follow the monitor's hardware mode";
          exec = "${config.home.homeDirectory}/.local/bin/display-mode --watch";
        };
      };
  };
}
