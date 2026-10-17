{
  inputs,
  ...
}:
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
        serviceConfig = {
          User = "buildkite-agent-main";
          Group = "buildkite-agent-main";
          Restart = "on-failure";
        };
        environment.BUILDKITE_REST_TOKEN_PATH = config.age.secrets.buildkite-rest-token.path;
        script = "exec ${pkgs.python3}/bin/python ${receiver}";
      };
    };
}
