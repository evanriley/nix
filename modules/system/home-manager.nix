{ config, inputs, ... }:
let
  inherit (config.meta) user;
  top = config;
in
{
  flake.homeConfigurations =
    inputs.nixpkgs.lib.mapAttrs'
      (host: system: {
        name = "${user.name}@${host}";
        value = inputs.home-manager.lib.homeManagerConfiguration {
          inherit (system) pkgs;
          modules = [ config.flake.modules.homeManager.${host} ];
        };
      })
      (
        inputs.nixpkgs.lib.filterAttrs (host: _: config.flake.modules.homeManager ? ${host}) (
          config.flake.nixosConfigurations // config.flake.darwinConfigurations or { }
        )
      );

  flake.modules.nixos.home-manager-vm =
    { config, lib, ... }:
    {
      virtualisation.vmVariant = {
        imports = [ inputs.home-manager.nixosModules.home-manager ];
        home-manager = {
          useGlobalPkgs = true;
          users.${user.name} = {
            imports = [ top.flake.modules.homeManager.${config.networking.hostName} ];
            dotfiles.mutable = false;
          };
        };
      };
    };

  flake.modules.homeManager.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      home.username = user.name;
      home.homeDirectory =
        if pkgs.stdenv.hostPlatform.isDarwin then "/Users/${user.name}" else "/home/${user.name}";
      home.stateVersion = "26.05";

      programs.home-manager.enable = true;
      xdg.enable = true;

      xdg.userDirs = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        enable = true;
        createDirectories = true;
        desktop = null;
        publicShare = null;
        templates = null;
        # niri's screenshot-path writes here.
        projects = "${config.home.homeDirectory}/Developer";
        extraConfig.SCREENSHOTS = "${config.home.homeDirectory}/Pictures/Screenshots";
      };
    };
}
