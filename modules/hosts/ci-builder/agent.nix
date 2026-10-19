{ config, ... }:
let
  nixos = config.flake.modules.nixos;
  inherit (config.meta) buildkiteJobPackages;
in
{
  meta.ciBuilderStartupScript = builtins.path {
    path = ./startup-script.sh;
    name = "ci-builder-startup-script.sh";
  };

  flake.modules.nixos.ci-builder-agent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      agent = "buildkite-agent-ci-builder";
      runtimeDir = "/run/ci-builder";
      credentialsDir = "/run/credentials/${agent}.service";

      fetchAndRunStartupScript = pkgs.writeShellApplication {
        name = "ci-builder-startup";
        runtimeInputs = [
          pkgs.bash
          pkgs.curl
        ];
        text = ''
          metadata() {
            curl --fail --silent --show-error \
              --connect-timeout 5 --max-time 30 \
              --retry 10 --retry-delay 2 --retry-connrefused \
              --header 'Metadata-Flavor: Google' \
              "http://169.254.169.254/computeMetadata/v1/instance/$1"
          }
          metadata name >${runtimeDir}/agent-name
          metadata attributes/startup-script >${runtimeDir}/startup-script
          exec bash ${runtimeDir}/startup-script
        '';
      };

      metadataChain = "ci-builder-metadata";
      metadataServers = [
        {
          command = "iptables";
          address = "169.254.169.254";
        }
        {
          command = "ip6tables";
          address = "fd20:ce::254";
        }
      ];
      jumpRule = address: "OUTPUT -d ${address} -j ${metadataChain}";
      startMetadataBlock =
        { command, address }:
        ''
          ${command} -w -D ${jumpRule address} 2>/dev/null || true
          ${command} -w -F ${metadataChain} 2>/dev/null || ${command} -w -N ${metadataChain}
          ${command} -w -A ${metadataChain} -p udp --dport 53 -j RETURN
          ${command} -w -A ${metadataChain} -p tcp --dport 53 -j RETURN
          ${command} -w -A ${metadataChain} -m owner --uid-owner ${agent} -j REJECT
          ${command} -w -A ${metadataChain} -m owner --gid-owner nixbld -j REJECT
          ${command} -w -I ${jumpRule address}
        '';
      stopMetadataBlock =
        { command, address }:
        ''
          ${command} -w -D ${jumpRule address} 2>/dev/null || true
          ${command} -w -F ${metadataChain} 2>/dev/null || true
          ${command} -w -X ${metadataChain} 2>/dev/null || true
        '';
    in
    {
      imports = [ nixos.nix-core ];

      services.buildkite-agents.ci-builder = {
        tokenPath = "${credentialsDir}/agent-token";
        name = "$(cat ${credentialsDir}/agent-name)";
        extraConfig = ''
          spawn=1
          disconnect-after-idle-timeout=300
        '';
        extraGroups = [ ];
        tags.queue = "spot-builders";
        runtimePackages = buildkiteJobPackages pkgs config.nix.package;
      };

      systemd.services.${agent} = {
        unitConfig = {
          ConditionPathExists = "${runtimeDir}/agent-token";
          SuccessAction = "poweroff";
          FailureAction = "poweroff";
        };
        serviceConfig = {
          LoadCredential = [
            "agent-token:${runtimeDir}/agent-token"
            "agent-name:${runtimeDir}/agent-name"
          ];
          Restart = lib.mkForce "no";
        };
      };

      systemd.services.ci-builder-startup = {
        description = "Fetch and run the GCE startup-script";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [
          "network-online.target"
          "multi-user.target"
        ];
        # The startup script runs switch-to-configuration from inside this unit.
        restartIfChanged = false;
        path = [ config.nix.package ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe fetchAndRunStartupScript;
          RuntimeDirectory = "ci-builder";
          RuntimeDirectoryMode = "0700";
          RuntimeDirectoryPreserve = true;
        };
      };

      networking.firewall = {
        enable = true;
        extraCommands = lib.concatMapStrings startMetadataBlock metadataServers;
        extraStopCommands = lib.concatMapStrings stopMetadataBlock metadataServers;
      };

      nix.settings = {
        max-jobs = 1;
        cores = 0;
      };
    };
}
