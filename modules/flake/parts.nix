{ inputs, lib, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.modules ];

  config.systems = [
    "x86_64-linux"
    "aarch64-darwin"
  ];

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
