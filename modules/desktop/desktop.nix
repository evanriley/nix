{ config, ... }:
let
  inherit (config.meta) user;

  # X11 support for niri and umbriel; Steam and Battle.net need it.
  # 0.8.3 fixes Steam menus closing instantly; drop once nixpkgs has it.
  xwaylandSatellite =
    pkgs:
    pkgs.xwayland-satellite.overrideAttrs (
      finalAttrs: old: {
        version = "0.8.3";
        src = old.src.override {
          tag = "v${finalAttrs.version}";
          hash = "sha256-eFEjCCniMCKeWU0PcZNv+tDYe08SLFPjRplyPY8OFt4=";
        };
        cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
          inherit (finalAttrs) pname version src;
          hash = "sha256-gMGFvnbxM3hD5fmkSimaFd87GEf6BXFe/MGjoS6VNVU=";
        };
      }
    );

  # xdg-desktop-portal reads only the current desktop's config, so each
  # compositor module adds these to its own xdg.portal.config entry.
  portalInterfaces = {
    "org.freedesktop.impl.portal.Settings" = [ "darkman" ];
    "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
    "org.freedesktop.impl.portal.Access" = [ "gtk" ];
    "org.freedesktop.impl.portal.Notification" = [ "gtk" ];
    "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
    "org.freedesktop.impl.portal.Inhibit" = [ "none" ];
  };
in
{
  flake.lib = { inherit xwaylandSatellite portalInterfaces; };

  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      networking.networkmanager.enable = true;
      programs.nm-applet.enable = true;
      users.users.${user.name}.extraGroups = [ "networkmanager" ];

      environment.systemPackages = [ (xwaylandSatellite pkgs) ];

      xdg.portal = {
        enable = true;
        extraPortals = [
          pkgs.xdg-desktop-portal-gnome
          pkgs.xdg-desktop-portal-gtk
          pkgs.darkman
          pkgs.gnome-keyring
        ];
      };

      services.gnome.gnome-keyring.enable = true;

      security.polkit.enable = true;
      programs.dconf.enable = true;
      services.gvfs.enable = true;
      services.udisks2.enable = true;

      security.pam.services.swaylock = { };

      environment.sessionVariables.NIXOS_OZONE_WL = "1";
    };
}
