{ config, ... }:
let
  inherit (config.flake.lib) portalInterfaces;
in
{
  flake.modules.nixos.niri = {
    programs.niri.enable = true;

    xdg.portal.config.niri = {
      default = [
        "gnome"
        "gtk"
      ];
    }
    // portalInterfaces;
  };

  flake.modules.homeManager.niri = {
    dotfiles.config = [ "niri" ];
  };
}
