{ inputs, lib, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.modules ];

  config.systems = [ "x86_64-linux" ];

  # Helpers shared between modules (flake.lib.<name>), merged across files.
  options.flake = lib.mkOption {
    type = lib.types.submoduleWith {
      modules = [
        {
          options.lib = lib.mkOption {
            type = lib.types.lazyAttrsOf lib.types.raw;
            default = { };
          };
        }
      ];
    };
  };
}
