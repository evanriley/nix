{
  flake.modules.nixos.blaziken =
    { ... }:
    let
      id = 7740;
      stateDir = "/var/lib/newsblur";
      address = "127.0.0.1";
      ports = {
        redis = 6579;
        mongo = 29019;
      };
      mongoUid = 999;
      elasticsearchUid = 1000;
    in
    {
      users.groups.newsblur.gid = id;
      users.users.newsblur = {
        isSystemUser = true;
        uid = id;
        group = "newsblur";
      };

      services.postgresql = {
        enable = true;
        ensureDatabases = [ "newsblur" ];
        ensureUsers = [
          {
            name = "newsblur";
            ensureDBOwnership = true;
          }
        ];
      };

      services.redis.servers.newsblur = {
        enable = true;
        bind = address;
        port = ports.redis;
        databases = 16;
        appendOnly = false;
      };

      boot.kernel.sysctl."vm.max_map_count" = 262144;

      virtualisation.oci-containers = {
        backend = "podman";
        containers = {
          newsblur-mongo = {
            image = "docker.io/library/mongo:4.0.28@sha256:f68f07e0c0ee86b1d848a30b27e5573e9c960748a02f7c288e28282297117644";
            cmd = [
              "--bind_ip"
              address
              "--port"
              (toString ports.mongo)
              "--wiredTigerCacheSizeGB"
              "1"
            ];
            volumes = [ "${stateDir}/mongo:/data/db" ];
            extraOptions = [ "--network=host" ];
          };
          newsblur-elasticsearch = {
            image = "docker.elastic.co/elasticsearch/elasticsearch:8.19.23@sha256:b6339612c7c680390be5c5472456a84ffbd6881e0216922ab3597c9c573950db";
            environment = {
              "discovery.type" = "single-node";
              "xpack.security.enabled" = "false";
              "network.host" = address;
              "cluster.routing.allocation.disk.threshold_enabled" = "false";
              ES_JAVA_OPTS = "-Xms1g -Xmx1g";
            };
            volumes = [ "${stateDir}/elasticsearch:/usr/share/elasticsearch/data" ];
            extraOptions = [ "--network=host" ];
          };
        };
      };

      systemd.tmpfiles.rules = [
        "d ${stateDir} 0755 root root -"
        "d ${stateDir}/mongo 0700 ${toString mongoUid} ${toString mongoUid} -"
        "d ${stateDir}/elasticsearch 0750 ${toString elasticsearchUid} 0 -"
      ];
    };
}
