{ config, pkgs, lib, ... }:

{


  imports = [
    <home-manager/nixos>
  ];

  # sym link dotfiles with home-manager
  home-manager.users.evan = { ... }: {

    # emacs/doom emacs
    home.file.".doom.d" = {
      source = ../../dotfiles/doom.d;
      recursive = true;
    };

    # swaywm and its friends
    home.file.".config/sway" = {
      source = ../../dotfiles/config/sway;
      recursive = true;
    };

    home.file.".config/waybar" = {
      source = ../../dotfiles/config/waybar;
      recursive = true;
    };

    home.file.".config/mako" = {
      source = ../../dotfiles/config/mako;
      recursive = true;
    };

    # zsh
    home.file.".zshrc" = {
      source = ../../dotfiles/zsh/zshrc;
    };

    # starship
    home.file.".config/starship.toml" = {
      source= ../../dotfiles/config/starship/starship.toml;
    };

    # git
    home.file.".gitconfig".source = ../../dotfiles/git/gitconfig;
    home.file.".gitconfig.local".source = ../../dotfiles/git/gitconfig.local;
    home.file.".gitignore".source = ../../dotfiles/git/gitignore;

    # vim
    home.file.".config/nvim" = {
      source = ../../dotfiles/nvim;
      recursive = true;
    };

  };
}
