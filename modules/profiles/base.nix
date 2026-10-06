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
    ai
  ];

  flake.modules.darwin.base.imports = with darwin; [
    nix
    secrets
    users
    networking
    shell
    ai
  ];

  flake.modules.homeManager.cli.imports = with homeManager; [
    base
    dotfiles
    shell
    git
    neovim
    theme
    ai
  ];
}
