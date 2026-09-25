{ config, ... }:
let
  inherit (config.flake.lib) mkScript;
in
{
  flake.modules.homeManager.cinderace =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      home.file.".local/bin/watch-media".source = lib.getExe (
        mkScript pkgs {
          name = "watch-media";
          src = ./_scripts/watch-media;
          runtimeInputs = [
            pkgs.fuzzel
            pkgs.findutils
            config.programs.mpv.finalPackage
          ];
        }
      );
    };
}
