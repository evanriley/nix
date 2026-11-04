{
  flake.modules.nixos.stacks =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      address = "127.0.0.1";
      id = 7788;
      ports = {
        stacks = 7788;
      };
      network = "stacks";
      podman = lib.getExe config.virtualisation.podman.package;
      tailscale = lib.getExe config.services.tailscale.package;
      flock = "${lib.getExe' pkgs.util-linux "flock"} /run/lock/tailscale-serve";

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
          ExecStart = "${flock} ${tailscale} serve --bg --https=${toString ports.${name}} http://${address}:${toString ports.${name}}";
          ExecStop = "${flock} ${tailscale} serve --https=${toString ports.${name}} off";
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
      users.groups.stacks.gid = id;
      users.users.stacks = {
        isSystemUser = true;
        uid = id;
        group = "stacks";
      };

      virtualisation.oci-containers = {
        backend = "podman";
        containers = {
          stacks = {
            image = "docker.io/zelest/stacks:v1.3.0@sha256:596d02602f80cef566b61b8abd3c1eee2bc6110c1a39b96401704d20cff71667";
            user = "${toString id}:${toString id}";
            networks = [ network ];
            ports = [ (publish "stacks") ];
            volumes = [
              "/var/lib/stacks/config:/opt/stacks/config"
              "/var/lib/stacks/logs:/opt/stacks/logs"
              "/var/lib/stacks/cache:/opt/stacks/cache"
              "/data/Downloads/stacks:/opt/stacks/download"
            ];
            environment = {
              TZ = config.time.timeZone;
              SOLVERR_URL = "http://flaresolverr:8191";
            };
            extraOptions = [
              "--stop-timeout=15"
              "--umask=0002"
            ];
          };
          flaresolverr = {
            image = "ghcr.io/flaresolverr/flaresolverr:v3.5.2@sha256:c80ae007ce2ccdcd217a12426e4f039ef763ff90738c808d38810c3e59323767";
            networks = [ network ];
            environment.TZ = config.time.timeZone;
          };
        };
      };

      systemd.tmpfiles.rules = [
        "d /var/lib/stacks 0750 stacks stacks -"
        "d /var/lib/stacks/config 0750 stacks stacks -"
        "d /var/lib/stacks/logs 0750 stacks stacks -"
        "d /var/lib/stacks/cache 0750 stacks stacks -"
        "d /data/Downloads/stacks 2775 stacks media -"
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

        podman-stacks = onNetwork // {
          after = onNetwork.after ++ [ "podman-flaresolverr.service" ];
          unitConfig.RequiresMountsFor = [ "/data" ];
        };
        podman-flaresolverr = onNetwork;

        stacks-tailscale-serve = serve "stacks" "Stacks";
      };

      services.borgmatic.configurations.home = {
        source_directories = [ "/var/lib/stacks" ];
        exclude_patterns = [
          "/var/lib/stacks/logs"
          "/var/lib/stacks/cache"
        ];
      };
    };
}
