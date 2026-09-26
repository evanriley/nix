{ config, inputs, ... }:
let
  inherit (config.meta) user;
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
        projects = "${config.home.homeDirectory}/Developer";
        # niri's screenshot-path writes here.
        extraConfig.SCREENSHOTS = "${config.home.homeDirectory}/Pictures/Screenshots";
      };
    };
}
