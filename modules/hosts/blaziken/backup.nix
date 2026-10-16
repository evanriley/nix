{ config, ... }:
let
  inherit (config.meta) secrets;
in
{
  flake.modules.nixos.blaziken =
    {
      config,
      pkgs,
      ...
    }:
    let
      ping = config.age.secrets.healthchecks-ping.path;
      bundleDirectory = "/var/backup/gerrit";
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
          "/var/backup"
        ];
        commands = [
          {
            before = "action";
            when = [ "create" ];
            run = [ "${bundleRepositories}" ];
          }
        ];
        hooks = {
          on_error = [ "curl --retry 3 $(cat ${ping})/fail" ];
        };
      };

      # after_backup fires per attempt, mid-retry, which would ping success on
      # a failing run; ExecStartPost only runs when the service actually
      # succeeded.
      systemd.services.borgmatic.serviceConfig.ExecStartPost = [
        "${pkgs.bash}/bin/sh -c 'curl --retry 3 $$(cat ${ping})'"
      ];

      systemd.tmpfiles.rules = [ "d ${bundleDirectory} 0700 root root -" ];

      systemd.services.borgmatic.path = [ pkgs.curl ];
    };
}
