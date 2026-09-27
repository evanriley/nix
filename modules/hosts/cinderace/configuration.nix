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
      base
      boot
      secure-boot
      zram
      nextdns
      yubikey
      desktop
      niri
      umbriel
      plymouth
      audio
      bluetooth
      fonts
      gaming
      media
      music
      navidrome
      backup
      syncthing
    ];

    networking.hostName = "cinderace";

    # Existing YubiKey pam-u2f registrations are bound to this origin.
    security.pam.u2f.settings = {
      origin = "pam://cinderance";
      appid = "pam://cinderance";
    };

    system.stateVersion = "26.05";
  };

  flake.modules.homeManager.cinderace =
    { pkgs, ... }:
    {
      imports = with homeManager; [
        workstation
        session
        niri
        umbriel
        apps
        music
        gaming
      ];

      home.stateVersion = "26.05";

      services.mpd.musicDirectory = "/mnt/Media/Music";

      programs.btop = {
        package = pkgs.btop.override {
          rocmSupport = true;
          rocmPackages = pkgs.rocmPackages // {
            # GPU names come from pci.ids at FHS paths only; without it btop shows 0x1002.
            # Drop once nixpkgs' rocm-smi points at hwdata.
            rocm-smi = pkgs.rocmPackages.rocm-smi.overrideAttrs (old: {
              postPatch = (old.postPatch or "") + ''
                substituteInPlace src/rocm_smi.cc \
                  --replace-fail '"/usr/share/hwdata/pci.ids"' '"${pkgs.hwdata}/share/hwdata/pci.ids"'
              '';
            });
          };
        };
        settings.shown_boxes = "cpu mem net proc gpu0";
      };

      # The existing profile; another path starts an empty one.
      programs.firefox.profiles.default.path = "b437d468.default-release";

      # File manager bookmarks; Nautilus writes through the link into the repo.
      dotfiles.config = [ "gtk-3.0/bookmarks" ];
    };
}
