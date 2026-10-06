{
  flake.modules.nixos.dispatcharr =
    { config, lib, ... }:
    let
      address = "127.0.0.1";
      id = 9191;
      ports = {
        dispatcharr = 9191;
        enhancedchannelmanager = 6100;
        teamarr = 9195;
      };
      network = "dispatcharr";
      podman = lib.getExe config.virtualisation.podman.package;
      tailscale = lib.getExe config.services.tailscale.package;

      publish = name: "${address}:${toString ports.${name}}:${toString ports.${name}}";

      serve = name: title: {
        description = "Serve ${title} on the tailnet";
        after = [
          "tailscaled.service"
          "podman-${name}.service"
        ];
        wants = [ "tailscaled.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStartPre = "${tailscale} wait --timeout=60s";
          ExecStart = "${tailscale} serve --bg --https=${toString ports.${name}} http://${address}:${toString ports.${name}}";
          ExecStop = "${tailscale} serve --https=${toString ports.${name}} off";
          Restart = "on-failure";
          RestartSec = 10;
        };
      };

      onNetwork = {
        requires = [ "podman-network-${network}.service" ];
        after = [ "podman-network-${network}.service" ];
      };
    in
    {
      users.groups.dispatcharr.gid = id;
      users.users.dispatcharr = {
        isSystemUser = true;
        uid = id;
        group = "dispatcharr";
      };

      virtualisation.oci-containers = {
        backend = "podman";
        containers = {
          dispatcharr = {
            image = "ghcr.io/dispatcharr/dispatcharr:0.31.0@sha256:f81924fa3dbfeb463b3908be7e086bf58aacbd2ba56062bfb555ee3a471acf8f";
            networks = [ network ];
            ports = [ (publish "dispatcharr") ];
            volumes = [ "/var/lib/dispatcharr:/data" ];
            environment = {
              DISPATCHARR_ENV = "aio";
              TZ = config.time.timeZone;
              PUID = toString id;
              PGID = toString id;
            };
            extraOptions = [ "--stop-timeout=15" ];
          };
          enhancedchannelmanager = {
            image = "ghcr.io/motwakorb/enhancedchannelmanager:0.18.1@sha256:2ef4645a618283264f2966b1db2ae387c9629ed254831fea4365bfec604fa0fb";
            networks = [ network ];
            ports = [ (publish "enhancedchannelmanager") ];
            volumes = [ "/var/lib/enhancedchannelmanager:/config" ];
            environment = {
              TZ = config.time.timeZone;
              PUID = toString id;
              PGID = toString id;
            };
          };
          teamarr = {
            image = "ghcr.io/pharaoh-labs/teamarr:2.21.1@sha256:a22432b76eeb4610909bd45aa17141b3c39fc99981c810949173d1b2fa263051";
            networks = [ network ];
            ports = [ (publish "teamarr") ];
            volumes = [ "/var/lib/teamarr:/app/data" ];
            environment.TZ = config.time.timeZone;
          };
        };
      };

      systemd.tmpfiles.rules = [
        "d /var/lib/dispatcharr 0750 dispatcharr dispatcharr -"
        "d /var/lib/enhancedchannelmanager 0750 dispatcharr dispatcharr -"
        "d /var/lib/teamarr 0750 root root -"
      ];

      systemd.services = {
        "podman-network-${network}" = {
          description = "Podman network ${network}";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${podman} network create --ignore ${network}";
          };
        };

        podman-dispatcharr = onNetwork;
        podman-enhancedchannelmanager = onNetwork;
        podman-teamarr = onNetwork;

        dispatcharr-tailscale-serve = serve "dispatcharr" "Dispatcharr";
        enhancedchannelmanager-tailscale-serve = serve "enhancedchannelmanager" "Enhanced Channel Manager";
        teamarr-tailscale-serve = serve "teamarr" "Teamarr";
      };

      services.borgmatic.configurations.home = {
        source_directories = [
          "/var/lib/dispatcharr"
          "/var/lib/enhancedchannelmanager"
          "/var/lib/teamarr"
        ];
        sqlite_databases = [
          {
            name = "enhancedchannelmanager";
            path = "/var/lib/enhancedchannelmanager/journal.db";
          }
          {
            name = "teamarr";
            path = "/var/lib/teamarr/teamarr.db";
          }
        ];
        exclude_patterns = [
          "/var/lib/dispatcharr/db"
          "/var/lib/dispatcharr/cache"
          "/var/lib/dispatcharr/logs"
          "/var/lib/dispatcharr/m3us"
          "/var/lib/dispatcharr/epgs"
          "sh:/var/lib/enhancedchannelmanager/journal.db*"
          "sh:/var/lib/teamarr/teamarr.db*"
          "/var/lib/teamarr/logs"
          "/var/lib/teamarr/epg_cache"
        ];
      };
    };
}
