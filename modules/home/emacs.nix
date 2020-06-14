{ config, pkgs, lib, ... }:

{
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = [ pkgs.emacs ];

  home-manager.users.evan = { ... }: {
    home.file.".doom.d" = {
      source = ../../dotfiles/doom.d;
      recursive = true;
    };
  };
}
