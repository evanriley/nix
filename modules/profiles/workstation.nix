{ config, ... }:
let
  inherit (config.flake.modules) homeManager;
in
{
  flake.modules.homeManager.workstation.imports = with homeManager; [
    cli
    firefox
    qutebrowser
    discord
    mpv
    bitwarden
    yubikey
  ];
}
