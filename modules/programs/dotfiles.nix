{ config, inputs, ... }:
let
  inherit (config.meta) repo;
in
{
  flake.modules.homeManager.dotfiles =
    { config, lib, ... }:
    let
      cfg = config.dotfiles;
      listOption =
        description:
        lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          inherit description;
        };
    in
    {
      options.dotfiles = {
        mutable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Link to the live checkout instead of the Nix store.";
        };
        link = lib.mkOption {
          type = lib.types.functionTo lib.types.raw;
          readOnly = true;
          description = "Path under home/ to a home.file source.";
        };
        config = listOption "Entries of home/config linked into ~/.config.";
      };

      config = {
        dotfiles.link =
          path:
          if cfg.mutable then
            config.lib.file.mkOutOfStoreSymlink "${repo}/home/${path}"
          else
            inputs.self + "/home/${path}";

        xdg.configFile = lib.genAttrs cfg.config (name: {
          source = cfg.link "config/${name}";
        });

        home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];
      };
    };
}
