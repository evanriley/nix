{ config, ... }:
let
  inherit (config.flake.modules) nixos darwin homeManager;
in
{
  flake.modules.nixos.base.imports = with nixos; [
    nix
    secrets
    users
    locale
    networking
    shell
  ];

  flake.modules.darwin.base.imports = with darwin; [
    nix
    secrets
    users
    networking
    shell
  ];

  flake.modules.homeManager.cli.imports = with homeManager; [
    base
    dotfiles
    shell
    git
    kakoune
    neovim
    theme
    ai
  ];
}
