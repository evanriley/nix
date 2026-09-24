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
      music
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

    home-manager.users.${user} = {
      imports = with homeManager; [
        base
        dotfiles
        shell
        kakoune
        session
        apps
        music
      ];

      services.mpd.musicDirectory = "/mnt/Media/Music";
      # watch-media browses /mnt/Media.
      dotfiles.config = [ "scripts" ];
      # Existing profile restored from the Arch home.
      programs.firefox.profiles.default.path = "b437d468.default-release";
    };

    system.stateVersion = "26.05";
  };
}
