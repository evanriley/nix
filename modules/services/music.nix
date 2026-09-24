{ inputs, config, ... }:
let
  inherit (config.meta) user;
in
{
  flake.modules.nixos.music = {
    age.secrets.listenbrainz-token = {
      file = inputs.self + "/secrets/listenbrainz-token.age";
      owner = user.name;
    };
  };

  flake.modules.homeManager.music =
    { config, pkgs, ... }:
    {
      programs.rmpc = {
        enable = true;
        config = ''
          (
              address: "127.0.0.1:6600",
              theme: Some("${config.xdg.configHome}/theme/rmpc.ron"),
          )
        '';
      };

      services.mpd = {
        enable = true;
        network.listenAddress = "127.0.0.1";
        playlistDirectory = "${config.services.mpd.dataDir}/playlists";
        extraConfig = ''
          auto_update "yes"
          audio_output {
            type "pulse"
            name "PipeWire"
            mixer_type "software"
          }
        '';
      };

      services.mpd-mpris = {
        enable = true;
        mpd.useLocal = true;
      };

      services.listenbrainz-mpd = {
        enable = true;
        settings = {
          submission.token_file = "/run/agenix/listenbrainz-token";
          mpd.address = "127.0.0.1:6600";
        };
      };
    };
}
