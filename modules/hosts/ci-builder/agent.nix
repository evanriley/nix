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
      inherit (config.ciBuilder) runtimeDir;
      credentialsDir = "/run/credentials/${agent}.service";
    in
    {
      imports = [
        nixos.ci-builder-base
        nixos.ci-builder-cache
      ];

      ciBuilder.metadataBlockedUsers = [ agent ];

      services.buildkite-agents.ci-builder = {
        tokenPath = "${credentialsDir}/agent-token";
        name = "$(cat ${credentialsDir}/agent-name)";
        extraConfig = ''
          spawn=1
          disconnect-after-idle-timeout=180
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

      systemd.services.ci-builder-agent-cancel = {
        description = "Cancel the running Buildkite job when the VM shuts down";
        wantedBy = [ "multi-user.target" ];
        after = [ "${agent}.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
          ExecStop = "-${config.systemd.package}/bin/systemctl kill --kill-whom=main --signal=SIGQUIT ${agent}.service";
        };
      };
    };
}
