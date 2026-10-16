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
      # Shares the buildkite agent's agenix secrets, so it runs as the agent.
      systemd.services.ci-trigger = {
        description = "Gerrit to Buildkite webhook receiver";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "buildkite-agent-blaziken";
          Group = "buildkite-agent-blaziken";
          Restart = "on-failure";
        };
        environment.BUILDKITE_REST_TOKEN_PATH = config.age.secrets.buildkite-rest-token.path;
        script = "exec ${pkgs.python3}/bin/python ${receiver}";
      };
    };
}
