{ config, ... }:
let
  inherit (config.flake.lib) portalInterfaces;
in
{
  flake.modules.nixos.niri =
    { pkgs, ... }:
    {
      programs.niri.enable = true;
      environment.systemPackages = [ pkgs.xwayland-satellite ];

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
