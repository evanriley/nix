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
        bin = listOption "Entries of home/bin linked into ~/.local/bin.";
        share = listOption "Entries of home/share linked into ~/.local/share.";
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

        home.file =
          lib.listToAttrs (
            map (name: lib.nameValuePair ".local/bin/${name}" { source = cfg.link "bin/${name}"; }) cfg.bin
          )
          // lib.listToAttrs (
            map (
              name: lib.nameValuePair ".local/share/${name}" { source = cfg.link "share/${name}"; }
            ) cfg.share
          );

        home.sessionPath = lib.mkIf (cfg.bin != [ ]) [ "${config.home.homeDirectory}/.local/bin" ];
      };
    };
}
