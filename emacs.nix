{ config, pkgs, lib, ... }:

{
  home.file.".doom.d" = {
      source = ../../dotfiles/doom.d;
      recursive = true;
    };

}
