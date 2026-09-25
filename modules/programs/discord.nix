{ config, ... }:
let
  inherit (config.flake.lib) sessionService;
in
{
  flake.modules.homeManager.discord =
    { lib, pkgs, ... }:
    {
      home.packages = [ pkgs.discord ];

      # Not niri spawn-at-startup: it dies in a race at login and niri discards its output.
      systemd.user.services.discord = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (sessionService {
        description = "Discord";
        exec = lib.getExe pkgs.discord;
      });
    };
}
