{ config, ... }:
let
  inherit (config.flake.modules) nixos;
in
{
  flake.modules.nixos.server.imports = with nixos; [
    nix
    secrets
    users
    locale
    networking
    shell
    zram
  ];
}
