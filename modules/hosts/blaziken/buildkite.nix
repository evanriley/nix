{
  config,
  inputs,
  ...
}:
let
  agent = "buildkite-agent-blaziken";
in
{
  flake.modules.nixos.blaziken =
    { config, pkgs, ... }:
    {
      services.buildkite-agents.blaziken = {
        tokenPath = config.age.secrets.buildkite-token.path;
        # The monorepo is public; pipelines clone over https without credentials.
        tags = {
          queue = "blaziken";
          host = "blaziken";
        };
        runtimePackages = [
          pkgs.bash
          pkgs.git
          pkgs.cachix
          config.nix.package
        ];
        hooks.environment = ''
          CACHIX_AUTH_TOKEN="$(cat ${config.age.secrets.cachix-token.path})"
          export CACHIX_AUTH_TOKEN
        '';
      };

      nix.settings.trusted-users = [
        "root"
        "@wheel"
        agent
      ];

      age.secrets.buildkite-token = {
        file = inputs.self + "/secrets/blaziken/buildkite-token.age";
        owner = agent;
      };

      age.secrets.cachix-token = {
        file = inputs.self + "/secrets/blaziken/cachix-token.age";
        owner = agent;
      };
    };
}
