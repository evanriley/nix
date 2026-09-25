{ config, ... }:
let
  inherit (config.flake.lib) sessionService mkScript;
  top = config;
in
{
  flake.modules.nixos.cinderace =
    { pkgs, ... }:
    {
      services.pipewire.extraConfig.pipewire."10-clock-rate"."context.properties" = {
        "default.clock.rate" = 48000;
        # Lets the DAC follow the source rate instead of resampling.
        "default.clock.allowed-rates" = [
          44100
          48000
          88200
          96000
          176400
          192000
        ];
      };

      # Suspending these sinks cuts audio in and pops on resume.
      services.pipewire.wireplumber.extraConfig."51-disable-usb-audio-suspend"."monitor.alsa.rules" = [
        {
          matches = [
            { "node.name" = "~alsa_output[.]usb-Topping_DX5_II-00[.].*"; }
            { "node.name" = "~alsa_output[.]usb-Fractal_Fractal_Scape_Dongle_.*"; }
          ];
          actions.update-props."session.suspend-timeout-seconds" = 0;
        }
      ];

      # uaccess only takes effect in rules sorted before 73-seat-late.rules.
      services.udev.packages = [
        (pkgs.writeTextDir "lib/udev/rules.d/70-scape.rules" ''
          SUBSYSTEM=="hidraw", ATTRS{idVendor}=="36bc", ATTRS{idProduct}=="0001", TAG+="uaccess"
        '')
      ];
    };

  flake.modules.homeManager.cinderace =
    { lib, pkgs, ... }:
    let
      scapectl = top.flake.packages.${pkgs.stdenv.hostPlatform.system}.scapectl;
    in
    {
      home.packages = [ scapectl ];

      xdg.configFile."scapectl/config.toml".source =
        let
          switch-audio = lib.getExe (
            mkScript pkgs {
              name = "switch-audio";
              src = ./_scripts/switch-audio;
              runtimeInputs = with pkgs; [
                wireplumber
                gawk
              ];
            }
          );
          trigger = event: sink: {
            inherit event;
            script = "${switch-audio} ${sink}";
            enabled = true;
            cooldown = 5;
          };
        in
        (pkgs.formats.toml { }).generate "scapectl-config.toml" {
          settings = {
            poll_interval_ms = 1500;
            tray_display = "white";
            tray_text = "Scape";
            triggers_enabled = true;
            verbose = false;
          };
          triggers = [
            (trigger "HeadsetPowerOn" "scape")
            (trigger "HeadsetPowerOff" "dx5")
          ];
        };

      systemd.user.services.scapectl = sessionService {
        description = "ScapeCtl headset tray";
        exec = lib.getExe scapectl;
      };
    };
}
