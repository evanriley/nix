{ config, ... }:
let
  inherit (config.meta) domain;
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
      inherit (config.mailserver) fqdn;
      dumpDirectory = "/var/backup/roundcube";
      dump = pkgs.writeShellApplication {
        name = "roundcube-dump";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.util-linux
          config.services.postgresql.package
        ];
        text = ''
          temporary="$(mktemp ${dumpDirectory}/.roundcube.pgdump.XXXXXX)"
          if ! runuser -u postgres -- pg_dump -Fc ${config.services.roundcube.database.dbname} > "$temporary"; then
            rm -f "$temporary"
            echo "Failed to dump the roundcube database; expected a running postgresql." >&2
            exit 1
          fi
          mv "$temporary" ${dumpDirectory}/roundcube.pgdump
        '';
      };
    in
    {
      services.roundcube = {
        enable = true;
        hostName = fqdn;
        package = pkgs.roundcube.withPlugins (p: [
          p.carddav
          p.persistent_login
        ]);
        plugins = [
          "managesieve"
          "carddav"
          "persistent_login"
          "archive"
          "zipdownload"
        ];
        maxAttachmentSize = config.mailserver.messageSizeLimit / (1024 * 1024);
        extraConfig = ''
          $config['imap_host'] = 'ssl://${fqdn}:993';
          $config['smtp_host'] = 'ssl://${fqdn}:465';
          $config['smtp_user'] = '%u';
          $config['smtp_pass'] = '%p';
          $config['managesieve_host'] = 'tls://${fqdn}:4190';
          $config['archive_mbox'] = 'Archive';
        '';
      };

      services.nginx.virtualHosts.${fqdn} = {
        enableACME = false;
        useACMEHost = domain;
      };

      systemd.tmpfiles.rules = [ "d ${dumpDirectory} 0700 root root -" ];

      systemd.services.roundcube-dump = {
        description = "Dump the Roundcube database for backup";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe dump;
        };
      };

      services.borgmatic.configurations.home = {
        source_directories = [ "/var/lib/roundcube" ];
        commands = [
          {
            before = "action";
            when = [ "create" ];
            run = [ "${config.systemd.package}/bin/systemctl start roundcube-dump.service" ];
          }
        ];
      };
    };
}
