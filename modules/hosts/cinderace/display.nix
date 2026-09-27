{ config, ... }:
let
  inherit (config.flake.lib) sessionService mkScript;
in
{
  # Samsung Odyssey G80HS on DP-2. Boot and login are pinned to 6K/165 so
  # Plymouth, the greeter and the compositor share one mode and the screen does
  # not blank. Switch the monitor to 6K before rebooting; display-mode follows
  # the monitor's 3K/330 mode inside niri and umbriel.
  flake.modules.nixos.cinderace = {
    boot.kernelParams = [
      "video=DP-2:6144x3456@165"
      "plymouth.use-simpledrm=0"
    ];

    services.displayManager.noctalia-greeter.settings.output = {
      name = "DP-2";
      width = 6144;
      height = 3456;
      refresh_rate = 165;
      scales = "DP-2:2";
    };
  };

  flake.modules.homeManager.cinderace =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      display-mode = mkScript pkgs {
        name = "display-mode";
        src = ./_scripts/display-mode;
        # steam comes from the system PATH (programs.steam).
        runtimeInputs = [
          pkgs.niri
          pkgs.wlr-randr
        ];
      };
    in
    {
      home.file.".local/bin/display-mode".source = lib.getExe display-mode;

      systemd.user.services.display-mode = sessionService {
        description = "Follow the monitor's hardware mode";
        exec = "${lib.getExe display-mode} --watch";
      };

      programs.umbriel.settings = {
        # No mode: umbriel reapplies this on every hotplug, and display-mode
        # picks the mode. The scale matches the 6K mode used at login.
        output.DP-2 = {
          scale = 2.0;
          # Fullscreen windows that request it, or match a tearing rule.
          tearing = true;
          hdr = "on";
        };
        keybinds."Mod+Ctrl+M" = {
          action = "spawn:${config.home.homeDirectory}/.local/bin/display-mode";
          repeat = false;
        };
      };

      # Full-size capture of the 6K mode makes niri's animations stutter.
      gaming.replay.size = "3072x1728";
    };
}
