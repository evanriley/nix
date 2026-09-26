{ config, inputs, ... }:
let
  inherit (config.meta) user;
in
{
  flake.modules.nixos.media =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      secret = name: inputs.self + "/secrets/${config.networking.hostName}/${name}.age";
      listenbrainzRecommendations =
        pkgs.runCommand "listenbrainz-recommendations"
          {
            buildInputs = [ pkgs.python3 ];
          }
          ''
            install -Dm755 ${./_listenbrainz-recommendations/listenbrainz-recommendations.py} \
              $out/bin/listenbrainz-recommendations
            patchShebangs $out/bin
          '';
    in
    {
      options.services.listenbrainz-recommendations.enable = lib.mkEnableOption "daily monitoring of ListenBrainz playlist albums in Lidarr";

      config = {
        users.groups.media = { };
        users.users.${user.name}.extraGroups = [ "media" ];

        age.secrets = {
          lidarr-env.file = secret "lidarr.env";
          slskd-env.file = secret "slskd.env";
          soularr-config.file = secret "soularr-config";
        };

        services.lidarr = {
          enable = true;
          dataDir = "/var/lib/lidarr";
          group = "media";
          environmentFiles = [ config.age.secrets.lidarr-env.path ];
          settings.server.bindaddress = "127.0.0.1";
        };

        services.slskd = {
          enable = true;
          group = "media";
          domain = null;
          openFirewall = true;
          environmentFile = config.age.secrets.slskd-env.path;
          settings = {
            web.ip_address = "127.0.0.1";
            web.https.disabled = true;
            directories = {
              incomplete = "/data/Downloads/slskd/incomplete";
              downloads = "/data/Downloads/slskd/complete";
            };
            shares = {
              directories = [ "/data/Music" ];
              cache.retention = 60;
            };
          };
        };

        systemd.services.lidarr.unitConfig.RequiresMountsFor = [ "/data" ];
        systemd.services.slskd.unitConfig.RequiresMountsFor = [ "/data" ];

        virtualisation.oci-containers = {
          backend = "podman";
          containers.soularr = {
            image = "docker.io/mrusse08/soularr:latest@sha256:9d17bdc35108afd747c4862dc32a0c1cba821638d170e1374188a977ce255c76";
            environment = {
              TZ = config.time.timeZone;
              SCRIPT_INTERVAL = "300";
              # Its unauthenticated /api/config serves config.ini, API keys included.
              WEBUI_ENABLED = "false";
            };
            volumes = [
              "/var/lib/soularr:/data"
              "${config.age.secrets.soularr-config.path}:/data/config.ini:ro"
              "/data/Downloads/slskd/complete:/downloads"
            ];
            # soularr-config points at Lidarr and slskd on 127.0.0.1.
            extraOptions = [ "--network=host" ];
          };
        };
        systemd.services.podman-soularr = {
          after = [
            "lidarr.service"
            "slskd.service"
          ];
          unitConfig.RequiresMountsFor = [ "/data" ];
        };
        systemd.tmpfiles.rules = [ "d /var/lib/soularr 0750 root root -" ];

        systemd.services.listenbrainz-recommendations =
          lib.mkIf config.services.listenbrainz-recommendations.enable
            {
              description = "Monitor albums from generated ListenBrainz playlists in Lidarr";
              after = [
                "lidarr.service"
                "network-online.target"
              ];
              requires = [ "lidarr.service" ];
              wants = [ "network-online.target" ];
              environment.PYTHONDONTWRITEBYTECODE = "1";
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${listenbrainzRecommendations}/bin/listenbrainz-recommendations --apply";
                EnvironmentFile = config.age.secrets.lidarr-env.path;
                DynamicUser = true;
                StateDirectory = "listenbrainz-recommendations";
                TimeoutStartSec = "1h";
                ProtectSystem = "strict";
                ProtectHome = true;
                PrivateTmp = true;
                NoNewPrivileges = true;
              };
            };
        systemd.timers.listenbrainz-recommendations =
          lib.mkIf config.services.listenbrainz-recommendations.enable
            {
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "*-*-* 10:00:00";
                RandomizedDelaySec = "30m";
                Persistent = true;
              };
            };
      };
    };
}
