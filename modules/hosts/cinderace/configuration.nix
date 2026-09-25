{ config, inputs, ... }:
let
  nixos = config.flake.modules.nixos;
  homeManager = config.flake.modules.homeManager;
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
      home-manager-vm
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

    system.stateVersion = "26.05";
  };

  flake.modules.homeManager.cinderace = {
    imports = with homeManager; [
      base
      dotfiles
      shell
      git
      kakoune
      neovim
      session
      theme
      apps
      qutebrowser
      music
      gaming
    ];

    services.mpd.musicDirectory = "/mnt/Media/Music";

    # Existing profile restored from the Arch home.
    programs.firefox.profiles.default.path = "b437d468.default-release";

    gtk.gtk3.bookmarks = [
      "file:///mnt/Games Games"
      "file:///mnt/Media Media"
    ];
  };
}
