{ config, ... }:
let
  inherit (config.meta) secrets;
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
      ping = config.age.secrets.healthchecks-ping.path;
      pocketIdDirectory = config.services.pocket-id.dataDir;
      crosspointSyncDirectory = "/var/lib/private/crosspoint-sync";
      rusticalDirectory = "/var/lib/private/rustical";
      bundleDirectory = "/var/backup/gerrit";
      sqlite3 = lib.getExe' pkgs.sqlite "sqlite3";
      dynamicUser = name: {
        DynamicUser = true;
        User = name;
        StateDirectory = name;
      };
      sqliteBackups = {
        pocket-id = {
          database = "${pocketIdDirectory}/data/pocket-id.db";
          serviceConfig = {
            User = "pocket-id";
            Group = "pocket-id";
            ProtectSystem = "strict";
            ReadWritePaths = [ "${pocketIdDirectory}/data" ];
          };
        };
        crosspoint-sync = {
          database = "/var/lib/crosspoint-sync/crosspoint.db";
          serviceConfig = dynamicUser "crosspoint-sync";
        };
        rustical = {
          database = "/var/lib/rustical/db.sqlite3";
          serviceConfig = dynamicUser "rustical";
        };
      };
      bundleRepositories = pkgs.writeShellScript "bundle-gerrit-repositories" ''
        set -euo pipefail
        for repository in /var/lib/gerrit/git/*.git; do
          name=$(basename "$repository" .git)
          temporary=$(mktemp ${bundleDirectory}/."$name".XXXXXX)
          trap 'rm -f "$temporary"' EXIT
          ${pkgs.git}/bin/git -c safe.directory='*' -C "$repository" bundle create "$temporary" --all
          mv "$temporary" ${bundleDirectory}/"$name".bundle
          trap - EXIT
        done
      '';
    in
    {
      age.secrets.healthchecks-ping = {
        file = secrets + "/blaziken/healthchecks-ping.age";
      };
      # The shared backup module already covers the user home and SSH host
      # keys; list concatenation adds the server state on top.
      services.borgmatic.configurations.home = {
        source_directories = [
          "/var/lib/gerrit"
          "/var/lib/git-bug"
          "/var/dkim"
          "/var/vmail"
          "/var/lib/redis-rspamd"
          "/var/backup"
          pocketIdDirectory
          crosspointSyncDirectory
          rusticalDirectory
        ];
        exclude_patterns = [
          "sh:${pocketIdDirectory}/data/pocket-id.db*"
          "sh:${crosspointSyncDirectory}/crosspoint.db*"
          "sh:${rusticalDirectory}/db.sqlite3*"
          "sh:/var/lib/git-bug/public"
        ];
        commands = [
          {
            before = "action";
            when = [ "create" ];
            run = [ "${bundleRepositories}" ];
          }
          {
            before = "action";
            when = [ "create" ];
            run = [
              "${config.systemd.package}/bin/systemctl start ${
                lib.concatMapStringsSep " " (name: "${name}-sqlite-backup.service") (lib.attrNames sqliteBackups)
              }"
            ];
          }
        ];
        hooks = {
          on_error = [ "curl --retry 3 $(cat ${ping})/fail" ];
        };
      };

      systemd.tmpfiles.rules = [ "d ${bundleDirectory} 0700 root root -" ];

      systemd.services =
        lib.mapAttrs' (
          name:
          { database, serviceConfig }:
          lib.nameValuePair "${name}-sqlite-backup" {
            description = "Back up the ${name} SQLite database";
            serviceConfig = serviceConfig // {
              Type = "oneshot";
              ExecStart = ''${sqlite3} -bail ${database} ".backup '${dirOf database}/backup.sqlite3'"'';
              UMask = "0077";
              PrivateTmp = true;
              NoNewPrivileges = true;
            };
          }
        ) sqliteBackups
        // {
          # after_backup fires per attempt, mid-retry, which would ping success on
          # a failing run; ExecStartPost only runs when the service actually
          # succeeded.
          borgmatic = {
            path = [ pkgs.curl ];
            serviceConfig.ExecStartPost = [
              "${pkgs.bash}/bin/sh -c 'curl --retry 3 $$(cat ${ping})'"
            ];
          };
        };
    };
}
