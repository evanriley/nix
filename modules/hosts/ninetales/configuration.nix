{ config, inputs, ... }:
let
  darwin = config.flake.modules.darwin;
  homeManager = config.flake.modules.homeManager;
  inherit (config.meta) user;
in
{
  flake.darwinConfigurations.ninetales = inputs.nix-darwin.lib.darwinSystem {
    modules = [ darwin.ninetales ];
  };

  flake.modules.darwin.ninetales = {
    imports = with darwin; [
      nix
      shell
    ];

    nixpkgs.hostPlatform = "aarch64-darwin";
    networking = {
      hostName = "ninetales";
      computerName = "ninetales";
      localHostName = "ninetales";
    };

    system.primaryUser = user.name;

    security.pam.services.sudo_local = {
      touchIdAuth = true;
      # Touch ID inside tmux.
      reattach = true;
    };

    # Requires Homebrew itself to be installed first (https://brew.sh).
    homebrew = {
      enable = true;
      casks = [ ];
      # Nothing is removed until casks are managed here.
      onActivation.cleanup = "none";
    };

    system.defaults = {
      NSGlobalDomain = {
        # 15 ms steps; 1 is the fastest repeat rate.
        InitialKeyRepeat = 10;
        KeyRepeat = 1;
      };
    };

    system.keyboard = {
      enableKeyMapping = true;
      remapCapsLockToControl = true;
    };

    system.stateVersion = 7;
  };

  flake.modules.homeManager.ninetales = {
    imports = with homeManager; [
      base
      dotfiles
      shell
      git
      kakoune
      neovim
      theme
      firefox
      mpv
      bitwarden
      ghostty
      syncthing
    ];
  };
}
