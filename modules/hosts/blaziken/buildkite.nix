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
    {
      config,
      lib,
      pkgs,
      ...
    }:
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
          pkgs.curl
          pkgs.jq
          pkgs.josh
          pkgs.openssh
          config.nix.package
        ];
        hooks.environment = ''
          CACHIX_AUTH_TOKEN="$(cat ${config.age.secrets.cachix-token.path})"
          BUILDKITE_API_TOKEN="$(cat ${config.age.secrets.buildkite-rest-token.path})"
          GERRIT_CI_KEY="${config.age.secrets.gerrit-ci-key.path}"
          GERRIT_KNOWN_HOSTS="${pkgs.writeText "gerrit-known-hosts" ''
            [git.maybemaybe.lol]:29418 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHGOzrLcNC9G05r/TC3Gldb+gKLK+OZwmLN0xKVE2RIO
          ''}"
          ORCA_MIRROR_KEY="${config.age.secrets.orca-mirror-key.path}"
          MANTA_MIRROR_KEY="${config.age.secrets.manta-mirror-key.path}"
          NIX_MIRROR_KEY="${config.age.secrets.nix-mirror-key.path}"
          ORCA_CACHIX_TOKEN="$(cat ${config.age.secrets.orca-cachix-token.path})"
          GITHUB_KNOWN_HOSTS="${pkgs.writeText "github-known-hosts" ''
            github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
          ''}"
          export CACHIX_AUTH_TOKEN BUILDKITE_API_TOKEN GERRIT_CI_KEY GERRIT_KNOWN_HOSTS
          export ORCA_MIRROR_KEY MANTA_MIRROR_KEY NIX_MIRROR_KEY ORCA_CACHIX_TOKEN GITHUB_KNOWN_HOSTS
        '';
      };

      systemd.services.${agent} = {
        # Restarting on activation kills the running job; SIGTERM lets it finish first.
        reloadIfChanged = true;
        serviceConfig = {
          Restart = lib.mkForce "always";
          RuntimeDirectory = agent;
          ExecReload = "${
            pkgs.writeShellApplication {
              name = "${agent}-stop-gracefully";
              runtimeInputs = [ pkgs.coreutils ];
              text = ''
                main_pid="$1"
                marker="$RUNTIME_DIRECTORY/graceful-stop-$main_pid"
                if [ ! -e "$marker" ]; then
                  touch "$marker"
                  kill -TERM "$main_pid" || true
                fi
              '';
            }
          }/bin/${agent}-stop-gracefully $MAINPID";
        };
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

      age.secrets.buildkite-rest-token = {
        file = inputs.self + "/secrets/blaziken/buildkite-rest-token.age";
        owner = agent;
      };

      age.secrets.gerrit-ci-key = {
        file = inputs.self + "/secrets/blaziken/gerrit-ci-key.age";
        owner = agent;
      };

      age.secrets.orca-mirror-key = {
        file = inputs.self + "/secrets/blaziken/orca-mirror-key.age";
        owner = agent;
      };

      age.secrets.manta-mirror-key = {
        file = inputs.self + "/secrets/blaziken/manta-mirror-key.age";
        owner = agent;
      };

      age.secrets.nix-mirror-key = {
        file = inputs.self + "/secrets/blaziken/nix-mirror-key.age";
        owner = agent;
      };

      age.secrets.orca-cachix-token = {
        file = inputs.self + "/secrets/blaziken/orca-cachix-token.age";
        owner = agent;
      };
    };
}
