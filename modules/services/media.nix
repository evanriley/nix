{ config, inputs, ... }:
let
  inherit (config.meta) user;
  inherit (config.flake.lib) mkScript;
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
      listenbrainzRecommendations = mkScript pkgs {
        name = "listenbrainz-recommendations";
        src = ./_listenbrainz-recommendations/listenbrainz-recommendations.py;
      };
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
        systemd.services.slskd = {
          unitConfig.RequiresMountsFor = [ "/data" ];
          # Lidarr (group media) must delete downloaded files when it imports them.
          serviceConfig.UMask = "0002";
        };

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
            extraOptions = [
              # soularr-config points at Lidarr and slskd on 127.0.0.1.
              "--network=host"
              # Import folders it creates must be group-writable so Lidarr can
              # move files out of them.
              "--umask=0002"
            ];
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

        services.borgmatic.configurations.home = {
          source_directories = [
            "/var/lib/lidarr"
            "/var/lib/slskd"
            "/var/lib/soularr"
            "/var/lib/private/listenbrainz-recommendations"
          ];
          # Lidarr writes its database continuously; back up a consistent dump
          # instead of the live file.
          sqlite_databases = [
            {
              name = "lidarr";
              path = "/var/lib/lidarr/lidarr.db";
            }
          ];
          exclude_patterns = [
            "sh:/var/lib/lidarr/lidarr.db*"
            "sh:/var/lib/lidarr/logs*"
            "/var/lib/lidarr/MediaCover"
          ];
        };

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
                ExecStart = "${lib.getExe listenbrainzRecommendations} --apply";
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
