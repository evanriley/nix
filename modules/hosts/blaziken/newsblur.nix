{ config, ... }:
let
  inherit (config.meta) secrets domain;
in
{
  flake.modules.nixos.blaziken =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      id = 7740;
      stateDir = "/var/lib/newsblur";
      address = "127.0.0.1";
      host = "news.${domain}";
      ports = {
        redis = 6579;
        mongo = 29019;
        web = 8000;
        node = 8008;
        imageproxy = 8088;
      };
      mongoUid = 999;
      elasticsearchUid = 1000;

      images = {
        python = "docker.io/newsblur/newsblur_python3:latest@sha256:87b282d2d94bc672f38a52724c97ed1c7005f9715c4a3469e96b28fdb632a016";
        node = "docker.io/newsblur/newsblur_node:latest@sha256:4bc67ff974e98d6aeb6c3f9b16386209b30163a8bb53070451cf6d00e56c70a5";
        imageproxy = "ghcr.io/willnorris/imageproxy:v0.11.2@sha256:72cac7ca33a6a3ccd64257e96beda5d59f6d7359152054540dd5fba8316cad24";
      };

      src = pkgs.applyPatches {
        name = "newsblur-source";
        src = pkgs.fetchFromGitHub {
          owner = "samuelclay";
          repo = "NewsBlur";
          rev = "c37bbad2266abcebe817c9a766452c2b0470690b";
          hash = "sha256-yF6rC3JvTSO4wjdc+QIYE5FOvlKmqFS+TpqtIhT3KJQ=";
        };
        patches = [
          ./newsblur/newsletters.patch
          ./newsblur/r2-storage.patch
          ./newsblur/senders.patch
          ./newsblur/subdomain.patch
          ./newsblur/webfeed-body.patch
        ];
        postPatch = ''
          cp ${./newsblur/local_settings.py} newsblur_web/local_settings.py
          cp ${./newsblur/gunicorn_local.py} config/gunicorn_local.py
          mkdir -p static .prom_cache node/originals
        '';
      };

      podman = lib.getExe config.virtualisation.podman.package;
      user = "${toString id}:${toString id}";
      envFile = config.age.secrets.newsblur-env.path;
      anthropicKeyFile = config.age.secrets.anthropic-key.path;

      hostNames = [
        "newsblur_db_postgres"
        "newsblur_db_mongo"
        "newsblur_db_mongo_analytics"
        "newsblur_db_redis"
        "newsblur_db_elasticsearch"
        "node"
        "haproxy"
      ];
      hostOptions = [ "--network=host" ] ++ map (name: "--add-host=${name}:${address}") hostNames;

      appEnvironment = {
        DOCKERBUILD = "True";
        TIKTOKEN_CACHE_DIR = "/srv/newsblur/logs/tiktoken";
      };
      appVolumes = [
        "${src}:/srv/newsblur:ro"
        "${stateDir}/logs:/srv/newsblur/logs"
        "${stateDir}/prom:/srv/newsblur/.prom_cache"
        "${stateDir}/static:/srv/newsblur/static"
        "/run/postgresql:/run/postgresql"
        "${anthropicKeyFile}:/run/secrets/anthropic-key:ro"
      ];
      app = cmd: {
        image = images.python;
        inherit user cmd;
        environment = appEnvironment;
        environmentFiles = [ envFile ];
        volumes = appVolumes;
        extraOptions = hostOptions;
      };

      siteCommand = ''
        from django.contrib.sites.models import Site
        Site.objects.update_or_create(pk=1, defaults={"domain": "${host}", "name": "NewsBlur"})
      '';
      setupCommand = lib.concatStringsSep " && " [
        "python manage.py migrate --noinput"
        "python manage.py collectstatic --no-input --clear -v 1"
        "python manage.py shell -c ${lib.escapeShellArg siteCommand}"
      ];
      setup = pkgs.writeShellScript "newsblur-setup" ''
        exec ${podman} run --rm --replace --name=newsblur-setup \
          --user ${user} \
          ${lib.escapeShellArgs hostOptions} \
          ${lib.escapeShellArgs (lib.mapAttrsToList (name: value: "-e=${name}=${value}") appEnvironment)} \
          -e PATH=/venv/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${pkgs.terser}/bin \
          --env-file ${envFile} \
          ${
            lib.escapeShellArgs (map (volume: "-v=${volume}") (appVolumes ++ [ "/nix/store:/nix/store:ro" ]))
          } \
          ${images.python} \
          sh -ec ${lib.escapeShellArg setupCommand}
      '';

      secretHashes = [
        (builtins.hashFile "sha256" config.age.secrets.newsblur-env.file)
        (builtins.hashFile "sha256" config.age.secrets.anthropic-key.file)
      ];
      afterSetup = {
        requires = [ "newsblur-setup.service" ];
        after = [ "newsblur-setup.service" ];
        restartTriggers = secretHashes;
      };

      proxy = target: extraConfig: {
        proxyPass = target;
        recommendedProxySettings = false;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_set_header X-Forwarded-Proto $scheme;
          ${extraConfig}
        '';
      };
      dumpDirectory = "/var/backup/newsblur";
      dump = pkgs.writeShellApplication {
        name = "newsblur-dump";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.util-linux
          config.services.postgresql.package
          config.virtualisation.podman.package
        ];
        text = ''
          write_dump() {
            local name="$1" temporary
            shift
            temporary="$(mktemp ${dumpDirectory}/."$name".XXXXXX)"
            if ! "$@" > "$temporary"; then
              rm -f "$temporary"
              echo "Failed to write $name with: $*; expected a running database." >&2
              return 1
            fi
            mv "$temporary" ${dumpDirectory}/"$name"
          }

          status=0
          write_dump newsblur.pgdump runuser -u postgres -- pg_dump -Fc newsblur || status=1
          write_dump mongo.archive.gz \
            podman exec newsblur-mongo mongodump --port ${toString ports.mongo} --archive --gzip || status=1
          exit "$status"
        '';
      };

      webUrl = "http://${address}:${toString ports.web}";
      nodeUrl = "http://${address}:${toString ports.node}";

      newsletterDomain = "newsletters.${host}";
      newsletterUser = "newsblur-newsletter";
      newsletterPipe = "newsblur-newsletter";
      newsletterDeliver = pkgs.writers.writePython3Bin "newsblur-newsletter" { } (
        builtins.readFile ./newsblur/newsletter.py
      );
      newsletterRecipients = pkgs.writeText "newsblur-newsletter-recipients" ''
        /^\w+[-+.]\w+@${lib.escapeRegex newsletterDomain}$/ OK
      '';
    in
    {
      age.secrets.newsblur-env.file = secrets + "/blaziken/newsblur.env.age";
      age.secrets.anthropic-key = {
        file = secrets + "/anthropic-key.age";
        owner = "newsblur";
        mode = "0400";
      };

      users.groups.newsblur.gid = id;
      users.users.newsblur = {
        isSystemUser = true;
        uid = id;
        group = "newsblur";
      };

      users.groups.${newsletterUser} = { };
      users.users.${newsletterUser} = {
        isSystemUser = true;
        group = newsletterUser;
      };

      services.postfix = {
        transport = "${newsletterDomain} ${newsletterPipe}:";
        settings.main = {
          relay_domains = [ newsletterDomain ];
          relay_recipient_maps = [ "pcre:${newsletterRecipients}" ];
          "${newsletterPipe}_destination_recipient_limit" = "1";
        };
        settings.master.${newsletterPipe} = {
          privileged = true;
          chroot = false;
          command = "pipe";
          args = [
            "flags=R"
            "user=${newsletterUser}"
            "argv=${lib.getExe newsletterDeliver}"
            "\${recipient}"
            "\${sender}"
          ];
        };
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
          newsblur-web = app [
            "gunicorn"
            "-c"
            "config/gunicorn_local.py"
            "newsblur_web.wsgi:application"
          ];
          newsblur-celery = app [
            "celery"
            "worker"
            "-A"
            "newsblur_web"
            "-B"
            "-s"
            "/srv/newsblur/logs/celerybeat-schedule.db"
            "-c"
            "4"
            "--loglevel=INFO"
          ];
          newsblur-node = {
            image = images.node;
            inherit user;
            cmd = [
              "node"
              "newsblur.js"
            ];
            environment = {
              NODE_ENV = "docker";
              MONGODB_PORT = toString ports.mongo;
            };
            environmentFiles = [ envFile ];
            volumes = [
              "${src}/node:/srv:ro"
              "${stateDir}/originals:/srv/originals"
            ];
            workdir = "/srv";
            extraOptions = hostOptions;
          };
          newsblur-imageproxy = {
            image = images.imageproxy;
            cmd = [
              "-addr"
              "${address}:${toString ports.imageproxy}"
              "-cache"
              "memory:200:4h"
            ];
            environmentFiles = [ envFile ];
            extraOptions = [ "--network=host" ];
          };
        };
      };

      systemd.services = {
        newsblur-setup = {
          description = "Migrate the NewsBlur database and collect its static files";
          requires = [
            "postgresql.target"
            "redis-newsblur.service"
            "podman-newsblur-mongo.service"
            "podman-newsblur-elasticsearch.service"
          ];
          after = [
            "network-online.target"
            "postgresql.target"
            "redis-newsblur.service"
            "podman-newsblur-mongo.service"
            "podman-newsblur-elasticsearch.service"
          ];
          wants = [ "network-online.target" ];
          restartTriggers = secretHashes;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = setup;
            TimeoutStartSec = "30min";
          };
        };
        podman-newsblur-web = afterSetup;
        podman-newsblur-celery = afterSetup;
        podman-newsblur-node = afterSetup;
        podman-newsblur-imageproxy.restartTriggers = [
          (builtins.hashFile "sha256" config.age.secrets.newsblur-env.file)
        ];
        newsblur-dump = {
          description = "Dump the NewsBlur databases for backup";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe dump;
          };
        };
      };

      services.borgmatic.configurations.home = {
        source_directories = [ "/var/lib/redis-newsblur" ];
        commands = [
          {
            before = "action";
            when = [ "create" ];
            run = [ "${config.systemd.package}/bin/systemctl start newsblur-dump.service" ];
          }
        ];
      };

      services.logrotate.settings."${stateDir}/logs/*.log" = {
        frequency = "daily";
        rotate = 14;
        compress = true;
        delaycompress = true;
        missingok = true;
        notifempty = true;
        copytruncate = true;
        su = "newsblur newsblur";
      };

      systemd.tmpfiles.rules = [
        "d ${stateDir} 0755 root root -"
        "d ${stateDir}/mongo 0700 ${toString mongoUid} ${toString mongoUid} -"
        "d ${stateDir}/elasticsearch 0750 ${toString elasticsearchUid} 0 -"
        "d ${stateDir}/logs 0750 newsblur newsblur -"
        "d ${stateDir}/prom 0750 newsblur newsblur -"
        "d ${stateDir}/originals 0750 newsblur newsblur -"
        "d ${stateDir}/static 0755 newsblur newsblur -"
        "d ${dumpDirectory} 0700 root root -"
      ];

      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "newsblur-manage";
          runtimeInputs = [ config.virtualisation.podman.package ];
          text = ''
            exec podman exec -it newsblur-web python manage.py "$@"
          '';
        })
      ];

      services.nginx = {
        appendHttpConfig = ''
          map $request_uri $newsblur_imageproxy_uri {
            default /;
            "~^/imageproxy(?<rest>/.*)$" $rest;
          }
        '';

        virtualHosts.${host} = {
          forceSSL = true;
          useACMEHost = domain;
          extraConfig = "client_max_body_size 20m;";
          locations = {
            "/" = proxy webUrl "";
            "/static/" = {
              alias = "${stateDir}/static/";
              extraConfig = "gzip_static on;";
            };
            "/media/".alias = "${src}/media/";
            "= /favicon.ico".alias = "${src}/media/img/favicon_32.png";
            "= /robots.txt".alias = "${src}/media/robots.txt";
            "= /crossdomain.xml".alias = "${src}/media/crossdomain.xml";
            "/v3/socket.io/" = proxy nodeUrl "proxy_read_timeout 3600s;" // {
              proxyWebsockets = true;
            };
            "/rss_feeds/icon/" = proxy nodeUrl "";
            "/listen/stream/" = proxy nodeUrl "";
            "/original_page/" = proxy nodeUrl "limit_except GET { deny all; }";
            "/imageproxy/" = proxy "http://${address}:${toString ports.imageproxy}$newsblur_imageproxy_uri" "";
            "/rss_feeds/original_text_fetcher".return = "404";
            "~ ^/newsletters/receive".return = "404";
            "~ ^/(account|api|reader)/signup".return = "404";
            "~ ^/signup/?$".return = "404";
            "~ ^/(account|api)/social/".return = "404";
          };
        };

        virtualHosts.newsblur-internal = {
          serverName = "haproxy";
          extraConfig = "client_max_body_size 20m;";
          listen = [
            {
              addr = address;
              port = 80;
            }
          ];
          locations = {
            "/rss_feeds/original_text_fetcher" = proxy nodeUrl "";
            "= /newsletters/receive" = {
              proxyPass = webUrl;
              recommendedProxySettings = false;
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Forwarded-For $remote_addr;
              '';
            };
            "/".return = "404";
          };
        };
      };
    };
}
