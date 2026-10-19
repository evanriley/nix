{ config, inputs, ... }:
let
  inherit (config.meta) ciBuilderStartupScript;
  fallbackDir = "/run/ci-spot-fallback";
in
{
  perSystem =
    { pkgs, system, ... }:
    inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
      checks.ci-spot-poller =
        pkgs.runCommand "ci-spot-poller-test"
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
            python -m pytest -p no:cacheprovider -v
            touch $out
          '';
    };

  flake.modules.nixos.blaziken =
    { config, pkgs, ... }:
    let
      poller = pkgs.writers.writePython3 "ci-spot-poller" {
        libraries = [ pkgs.python3Packages.cryptography ];
      } (builtins.readFile ./ci-spot-poller.py);
      mainAgent = "buildkite-agent-main";
    in
    {
      systemd.services.ci-spot-poller = {
        description = "Launch GCE spot builders for the spot-builders queue";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        environment = {
          BUILDKITE_AGENT_TOKEN_PATH = config.age.secrets.buildkite-token.path;
          GCP_KEY_PATH = config.age.secrets.gcp-ci-key.path;
          CI_BUILDER_SYSTEM_FILE = "${config.services.buildkite-agents.main.dataDir}/ci-builder-system";
          CI_BUILDER_STARTUP_SCRIPT = "${ciBuilderStartupScript}";
          CI_SPOT_FALLBACK_REQUEST = "${fallbackDir}/request";
        };
        serviceConfig = {
          User = mainAgent;
          Group = mainAgent;
          ExecStart = poller;
          Restart = "always";
          RestartSec = 30;
          UMask = "0077";
          NoNewPrivileges = true;
          CapabilityBoundingSet = "";
          ProtectSystem = "strict";
          ReadWritePaths = [ fallbackDir ];
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectProc = "invisible";
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "~@privileged @resources"
          ];
        };
      };

      systemd.tmpfiles.rules = [ "d ${fallbackDir} 0700 ${mainAgent} ${mainAgent} -" ];

      systemd.paths.ci-spot-fallback = {
        description = "Start the spot-builders fallback agent on request";
        wantedBy = [ "paths.target" ];
        pathConfig = {
          PathChanged = "${fallbackDir}/request";
          Unit = "buildkite-agent-spot-fallback.service";
        };
      };
    };
}
