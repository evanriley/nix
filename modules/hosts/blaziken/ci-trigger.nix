{ config, ... }:
let
  inherit (config.meta) gerritKnownHosts domain;
in
{
  flake.modules.nixos.blaziken =
    { config, pkgs, ... }:
    let
      receiver = pkgs.writers.writePython3 "ci-trigger" { } (builtins.readFile ./ci-trigger.py);
    in
    {
      systemd.services.ci-trigger = {
        description = "Gerrit to Buildkite webhook receiver";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.openssh ];
        serviceConfig = {
          User = "buildkite-agent-main";
          Group = "buildkite-agent-main";
          Restart = "on-failure";
        };
        environment = {
          BUILDKITE_REST_TOKEN_PATH = config.age.secrets.buildkite-rest-token.path;
          GERRIT_SSH_KEY_PATH = config.age.secrets.gerrit-ci-key.path;
          GERRIT_KNOWN_HOSTS_PATH = pkgs.writeText "gerrit-known-hosts" "${gerritKnownHosts}\n";
          GERRIT_SSH_DESTINATION = "buildkite@git.${domain}";
        };
        script = "exec ${pkgs.python3}/bin/python ${receiver}";
      };
    };
}
