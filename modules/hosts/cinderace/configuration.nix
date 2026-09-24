{ config, inputs, ... }:
let
  nixos = config.flake.modules.nixos;
  homeManager = config.flake.modules.homeManager;
  user = config.meta.user.name;
in
{
  flake.nixosConfigurations.cinderace = inputs.nixpkgs.lib.nixosSystem {
    modules = [ nixos.cinderace ];
  };

  flake.modules.nixos.cinderace = {
    imports = with nixos; [
      nix
      boot
      secure-boot
      secrets
      users
      home-manager
      locale
      networking
      yubikey
      desktop
      audio
      bluetooth
      fonts
      shell
      gaming
      media
      backup
      syncthing
      vm
    ];

    networking.hostName = "cinderace";

    # Existing YubiKey pam-u2f registrations are bound to this origin.
    security.pam.u2f.settings = {
      origin = "pam://cinderance";
      appid = "pam://cinderance";
    };

    home-manager.users.${user}.imports = with homeManager; [
      base
      dotfiles
      shell
      kakoune
      session
      apps
      music
    ];

    system.stateVersion = "26.05";
  };
}
