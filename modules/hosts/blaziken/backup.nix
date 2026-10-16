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

      systemd.services.borgmatic.path = [ pkgs.curl ];
    };
}
