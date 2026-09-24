{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      services.displayManager.gdm.enable = true;
      programs.niri.enable = true;

      environment.systemPackages = [
        # niri's X11 support; Steam and Battle.net need it.
        pkgs.xwayland-satellite
      ];

      xdg.portal = {
        enable = true;
        extraPortals = [
          pkgs.xdg-desktop-portal-gnome
          pkgs.xdg-desktop-portal-gtk
          # Settings portal: apps follow darkman's light/dark mode.
          pkgs.darkman
        ];
      };

      services.gnome.gnome-keyring.enable = true;
      security.pam.services.gdm-password.enableGnomeKeyring = true;

      security.polkit.enable = true;
      programs.dconf.enable = true;
      services.gvfs.enable = true;
      services.udisks2.enable = true;

      security.pam.services.swaylock = { };

      environment.sessionVariables.NIXOS_OZONE_WL = "1";
    };
}
