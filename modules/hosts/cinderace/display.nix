{
  # Boot and login are pinned to 6K/165 so Plymouth, GDM and niri share one
  # mode and the screen does not blank. Switch the monitor to 6K before
  # rebooting; display-mode handles 3K/330 inside niri.
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
}
