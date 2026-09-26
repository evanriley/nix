{ config, ... }:
let
  inherit (config.meta) user;
in
{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      services.displayManager.gdm.enable = true;
      programs.niri.enable = true;

      networking.networkmanager.enable = true;
      programs.nm-applet.enable = true;
      users.users.${user.name}.extraGroups = [ "networkmanager" ];

      environment.systemPackages = [
        # niri's X11 support; Steam and Battle.net need it.
        # 0.8.3 fixes Steam menus closing instantly; drop once nixpkgs has it.
        (pkgs.xwayland-satellite.overrideAttrs (
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
        ))
      ];

      xdg.portal = {
        enable = true;
        extraPortals = [
          pkgs.xdg-desktop-portal-gnome
          pkgs.xdg-desktop-portal-gtk
          pkgs.darkman
          pkgs.gnome-keyring
        ];
        config.niri = {
          default = [
            "gnome"
            "gtk"
          ];
          "org.freedesktop.impl.portal.Settings" = [ "darkman" ];
          "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
          "org.freedesktop.impl.portal.Access" = [ "gtk" ];
          "org.freedesktop.impl.portal.Notification" = [ "gtk" ];
          "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
        };
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
