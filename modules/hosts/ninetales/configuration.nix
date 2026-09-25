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
        AppleInterfaceStyleSwitchesAutomatically = true;
        "com.apple.swipescrolldirection" = false;
        "com.apple.mouse.tapBehavior" = 1;
      };

      dock = {
        autohide = true;
        orientation = "bottom";
        magnification = false;
        show-recents = false;
        # Home Manager copies apps here; a Nix store path would break the pins on every rebuild.
        persistent-apps = [
          "/Users/${user.name}/Applications/Home Manager Apps/Firefox.app"
          "/Users/${user.name}/Applications/Home Manager Apps/Ghostty.app"
        ];
        persistent-others = [ ];
        wvous-tl-corner = 1;
        wvous-tr-corner = 1;
        wvous-bl-corner = 1;
        wvous-br-corner = 1;
      };

      WindowManager.GloballyEnabled = false;
      controlcenter.BatteryShowPercentage = true;
      trackpad.Clicking = true;
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
      qutebrowser
      discord
      mpv
      bitwarden
      ghostty
      syncthing
    ];
  };
}
