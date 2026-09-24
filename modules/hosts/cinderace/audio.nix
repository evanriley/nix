{ config, ... }:
let
  inherit (config.flake.lib) sessionService;
  top = config;
in
{
  # Topping DX5 II (speakers) and Fractal Scape (headset). ScapeCtl switches
  # the default sink when the headset powers on or off.
  flake.modules.nixos.cinderace = {
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

    services.udev.extraRules = ''
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="36bc", ATTRS{idProduct}=="0001", TAG+="uaccess"
    '';
  };

  flake.modules.homeManager.cinderace =
    { lib, pkgs, ... }:
    let
      scapectl = top.flake.packages.${pkgs.stdenv.hostPlatform.system}.scapectl;
    in
    {
      dotfiles.config = [ "scapectl" ];
      home.packages = [ scapectl ];

      systemd.user.services.scapectl = sessionService {
        description = "ScapeCtl headset tray";
        exec = lib.getExe scapectl;
      };
    };
}
