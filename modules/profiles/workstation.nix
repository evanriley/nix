{ config, ... }:
let
  inherit (config.flake.modules) nixos homeManager;
in
{
  flake.modules.nixos.workstation.imports = with nixos; [
    base
    boot
    zram
    nextdns
    yubikey
    desktop
    umbriel
    noctalia
    plymouth
    audio
    bluetooth
    fonts
    obs
  ];

  flake.modules.homeManager.workstation.imports = with homeManager; [
    cli
    firefox
    qutebrowser
    discord
    mpv
    bitwarden
    yubikey
  ];

  flake.modules.homeManager.desktop.imports = with homeManager; [
    workstation
    session
    umbriel
    noctalia
    apps
  ];
}
