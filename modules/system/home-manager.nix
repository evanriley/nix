{ config, inputs, ... }:
let
  inherit (config.meta) user;
in
{
  flake.modules.nixos.home-manager = {
    imports = [ inputs.home-manager.nixosModules.home-manager ];

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "hm-backup";
    };
  };

  flake.modules.homeManager.base = {
    home.username = user.name;
    home.homeDirectory = "/home/${user.name}";
    home.stateVersion = "26.05";

    programs.home-manager.enable = true;
    xdg.enable = true;
  };
}
