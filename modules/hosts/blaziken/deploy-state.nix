{
  flake.modules.nixos.blaziken =
    { config, lib, ... }:
    let
      newsblurContainers = lib.filterAttrs (
        name: _: lib.hasPrefix "newsblur-" name
      ) config.virtualisation.oci-containers.containers;
      newsblurSetup = config.systemd.services.newsblur-setup.serviceConfig.ExecStart;
      redisKey = [ config.services.redis.package.version ];
    in
    {
      deployState.enforce = true;

      deployState.entries = {
        rustical = {
          key = [ "${config.services.rustical.package}" ];
          units = [ "rustical.service" ];
          paths = [ "/var/lib/private/rustical" ];
        };

        pocket-id = {
          key = [ "${config.services.pocket-id.package}" ];
          units = [ "pocket-id.service" ];
          paths = [ config.services.pocket-id.dataDir ];
        };

        crosspoint-sync = {
          key = [ "${config.systemd.services.crosspoint-sync.serviceConfig.ExecStart}" ];
          units = [ "crosspoint-sync.service" ];
          paths = [ "/var/lib/private/crosspoint-sync" ];
        };

        gerrit = {
          key = [
            "${config.services.gerrit.package}"
          ]
          ++ map toString config.services.gerrit.plugins
          ++ config.services.gerrit.builtinPlugins;
          units = [
            "gerrit.socket"
            "gerrit.service"
            "git-bug-sync.timer"
            "git-bug-sync.service"
          ];
          paths = [ "/var/lib/gerrit" ];
        };

        git-bug = {
          key = [ "${config.systemd.services.git-bug-webui.serviceConfig.ExecStart}" ];
          units = [
            "git-bug-webui.service"
            "git-bug-webui-public.service"
            "git-bug-sync.timer"
            "git-bug-sync.service"
          ];
          paths = [
            "/var/lib/git-bug"
            "/var/lib/git-bug-public"
          ];
        };

        postgresql = {
          key = [
            config.services.postgresql.package.version
            "${config.services.roundcube.package}"
            "${newsblurSetup}"
          ];
          units = [ "postgresql.service" ];
          paths = [ "/var/lib/postgresql" ];
        };

        newsblur = {
          key = lib.mapAttrsToList (_: container: container.image) newsblurContainers ++ [
            "${newsblurSetup}"
          ];
          units = [
            "newsblur-setup.service"
          ]
          ++ map (name: "podman-${name}.service") (lib.attrNames newsblurContainers);
          paths = [ "/var/lib/newsblur" ];
        };

        redis-rspamd = {
          key = redisKey;
          units = [ "redis-rspamd.service" ];
          paths = [ "/var/lib/redis-rspamd" ];
        };

        redis-newsblur = {
          key = redisKey;
          units = [ "redis-newsblur.service" ];
          paths = [ "/var/lib/redis-newsblur" ];
        };
      };

      deployState.exempt = {
        "/var/lib/acme" =
          "lego re-issues certificates and account keys on demand, and its files carry no forward-only schema";
        "/var/lib/blaziken-deploy" =
          "holds the deploy snapshot itself, the backup stamp and boot-trial markers; none is migrated by a service";
        "/var/lib/buildkite-agent-spot-fallback" =
          "agent working directory and build checkouts; a new agent version recreates them";
        "/var/lib/knot-resolver" = "resolver cache, rebuilt on start";
        "/var/lib/nginx" = "proxy and temporary files, recreated by nginx";
        "/var/lib/roundcube" =
          "generated configuration and temporary files; the database is in /var/lib/postgresql";
        "/var/lib/rspamd" =
          "statistics live in redis-rspamd, which is registered; rspamd regenerates the rest";
        "/var/lib/systemd/linger" = "logind linger marker files, one empty file per user";
        "/var/lib/zoekt" = "search index and clone, rebuilt by zoekt-index from the Gerrit repository";
      };
    };
}
