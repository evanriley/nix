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

  flake.modules.darwin.ninetales =
    { config, ... }:
    let
      inherit (config.users.users.${user.name}) home;
    in
    {
      imports = with darwin; [
        base
        nextdns
        backup
        omniwm
      ];

      nixpkgs.hostPlatform = "aarch64-darwin";
      networking = {
        hostName = "ninetales";
        computerName = "ninetales";
        localHostName = "ninetales";
      };

      security.pam.services.sudo_local = {
        touchIdAuth = true;
        # Touch ID inside tmux.
        reattach = true;
      };

      # Requires Homebrew itself to be installed first (https://brew.sh).
      homebrew = {
        enable = true;
        casks = [
          "firefox"
          "helium-browser"
          "obs"
        ];
        # Nothing is removed until casks are managed here.
        onActivation.cleanup = "none";
      };

      system.defaults = {
        NSGlobalDomain = {
          InitialKeyRepeat = 10;
          KeyRepeat = 1;
          AppleInterfaceStyleSwitchesAutomatically = true;
          "com.apple.swipescrolldirection" = false;
          "com.apple.mouse.tapBehavior" = 1;
          AppleShowScrollBars = "Always";
          AppleShowAllExtensions = true;
          AppleShowAllFiles = true;
          NSAutomaticSpellingCorrectionEnabled = false;
          NSAutomaticQuoteSubstitutionEnabled = false;
          NSAutomaticDashSubstitutionEnabled = false;
          NSAutomaticCapitalizationEnabled = false;
          NSAutomaticPeriodSubstitutionEnabled = false;
          ApplePressAndHoldEnabled = false;
        };

        finder = {
          AppleShowAllExtensions = true;
          AppleShowAllFiles = true;
          FXEnableExtensionChangeWarning = false;
          ShowPathbar = true;
          ShowStatusBar = true;
          _FXShowPosixPathInTitle = true;
          FXPreferredViewStyle = "Nlsv";
          NewWindowTarget = "Home";
        };

        dock = {
          autohide = true;
          orientation = "bottom";
          magnification = false;
          show-recents = false;
          mru-spaces = false;
          persistent-apps = [
            "/Applications/Firefox.app"
            "${home}/Applications/Home Manager Apps/Ghostty.app"
          ];
          persistent-others = [ ];
          wvous-tl-corner = 1;
          wvous-tr-corner = 1;
          wvous-bl-corner = 1;
          wvous-br-corner = 1;
        };

        WindowManager = {
          GloballyEnabled = false;
          EnableStandardClickToShowDesktop = false;
        };
        spaces.spans-displays = false;

        screencapture = {
          location = "${home}/Pictures/Screenshots";
          type = "png";
          disable-shadow = true;
          show-thumbnail = false;
        };

        menuExtraClock = {
          Show24Hour = false;
          ShowAMPM = true;
          ShowDate = 1;
          ShowDayOfWeek = true;
          ShowDayOfMonth = true;
        };

        screensaver = {
          askForPassword = true;
          askForPasswordDelay = 0;
        };
        loginwindow.GuestEnabled = false;
        controlcenter.BatteryShowPercentage = true;
        trackpad.Clicking = true;

        CustomUserPreferences."com.apple.Spotlight".EnabledPreferenceRules = [
          "Custom.relatedContents"
          "com.apple.AppStore"
          "com.apple.iBooksX"
          "com.apple.calculator"
          "com.apple.iCal"
          "com.apple.AddressBook"
          "com.apple.Dictionary"
          "com.apple.mail"
          "com.apple.MobileSMS"
          "com.apple.Notes"
          "com.apple.Photos"
          "com.apple.podcasts"
          "com.apple.reminders"
          "com.apple.Safari"
          "com.apple.shortcuts"
          "com.apple.systempreferences"
          "com.apple.tips"
          "com.apple.VoiceMemos"
          "System.files"
          "System.folders"
          "System.iphoneApps"
          "System.menuItems"
        ];
      };

      system.startup.chime = false;

      system.keyboard = {
        enableKeyMapping = true;
        remapCapsLockToControl = true;
      };

      system.stateVersion = 7;
    };

  flake.modules.homeManager.ninetales =
    { lib, ... }:
    {
      imports = with homeManager; [
        workstation
        ghostty
        syncthing
        omniwm
      ];

      home.stateVersion = "26.05";

      home.activation.screenshotsDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p "$HOME/Pictures/Screenshots"
      '';
    };
}
