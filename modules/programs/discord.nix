{ config, ... }:
let
  inherit (config.flake.lib) sessionService;
in
{
  flake.modules.homeManager.discord =
    { lib, pkgs, ... }:
    {
      home.packages = [ pkgs.discord ];

      # spawn-at-startup lost it to a race at login and discarded its output.
      systemd.user.services.discord = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (sessionService {
        description = "Discord";
        exec = lib.getExe pkgs.discord;
      });
    };
}
