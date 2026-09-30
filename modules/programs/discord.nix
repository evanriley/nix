{ config, ... }:
let
  inherit (config.flake.lib) sessionService;
in
{
  flake.modules.homeManager.discord =
    { lib, pkgs, ... }:
    {
      home.packages = [ pkgs.discord ];

      systemd.user.services.discord = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (sessionService {
        description = "Discord";
        exec = lib.getExe pkgs.discord;
      });
    };
}
