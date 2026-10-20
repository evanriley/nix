{ config, ... }:
let
  nixos = config.flake.modules.nixos;
in
{
  flake.modules.nixos.ci-builder-base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.ciBuilder;

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
          metadata name >${cfg.runtimeDir}/agent-name
          metadata attributes/startup-script >${cfg.runtimeDir}/startup-script
          exec bash ${cfg.runtimeDir}/startup-script
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
        ''
        + lib.concatMapStrings (user: ''
          ${command} -w -A ${metadataChain} -m owner --uid-owner ${user} -j REJECT
        '') cfg.metadataBlockedUsers
        + ''
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

      options.ciBuilder = {
        runtimeDir = lib.mkOption {
          type = lib.types.str;
          default = "/run/ci-builder";
          readOnly = true;
          description = "Root-only directory where the startup runner keeps the fetched startup-script and its state.";
        };

        metadataBlockedUsers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Users that, like the nixbld group, may not reach the GCE metadata server except for DNS.";
        };
      };

      config = {
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
          unitConfig.FailureAction = "poweroff";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe fetchAndRunStartupScript;
            StandardOutput = "journal+console";
            StandardError = "journal+console";
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
    };
}
