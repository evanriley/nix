{ config, inputs, ... }:
let
  inherit (config.meta) secrets ciRemoteBuilderStartupScript;
in
{
  perSystem =
    { pkgs, system, ... }:
    inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
      checks.ci-remote-builder-lease =
        pkgs.runCommand "ci-remote-builder-lease-test"
          {
            nativeBuildInputs = [
              (pkgs.python3.withPackages (python: [
                python.cryptography
                python.pytest
              ]))
            ];
          }
          ''
            cp ${./ci-spot-poller.py} ci_spot_poller.py
            cp ${./ci-spot-poller-test.py} test_ci_spot_poller.py
            cp ${./ci-remote-builder.py} ci_remote_builder.py
            cp ${./ci-remote-builder-test.py} test_ci_remote_builder.py
            python -m pytest -p no:cacheprovider -v test_ci_remote_builder.py
            touch $out
          '';
    };

  flake.modules.nixos.blaziken =
    { config, pkgs, ... }:
    let
      python = pkgs.python3Packages;
      spotPoller = python.toPythonModule (
        pkgs.runCommand "ci-spot-poller-module" { } ''
          install -D -m 444 ${./ci-spot-poller.py} $out/${pkgs.python3.sitePackages}/ci_spot_poller.py
        ''
      );
      remoteBuilder = pkgs.writers.writePython3 "ci-remote-builder" {
        libraries = [
          python.cryptography
          spotPoller
        ];
      } (builtins.readFile ./ci-remote-builder.py);
      cli = pkgs.writeShellApplication {
        name = "ci-remote-builder";
        text = ''
          export GCP_KEY_PATH=${config.age.secrets.gcp-ci-key.path}
          export CI_REMOTE_BUILDER_STARTUP_SCRIPT=${ciRemoteBuilderStartupScript}
          export CI_REMOTE_BUILDER_SSH_KEY=${config.age.secrets.ci-remote-builder-key.path}
          export CI_REMOTE_BUILDER_SYSTEM_FILE=${config.services.buildkite-agents.main.dataDir}/ci-remote-builder-system
          exec ${remoteBuilder} "$@"
        '';
      };
    in
    {
      services.buildkite-agents.main.runtimePackages = [ cli ];

      nix.settings.trusted-users = [ "buildkite-agent-main" ];

      age.secrets.ci-remote-builder-key = {
        file = secrets + "/blaziken/ci-remote-builder-key.age";
        owner = "root";
        mode = "0400";
      };
    };
}
