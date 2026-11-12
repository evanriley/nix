{ config, ... }:
let
  inherit (config.meta) gerritKnownHosts domain;
in
{
  flake.modules.nixos.blaziken =
    { config, pkgs, ... }:
    let
      receiver = pkgs.writers.writePython3 "ci-trigger" { } (builtins.readFile ./ci-trigger.py);
      port = 8470;
      onlyGerritRule = "OUTPUT -o lo -p tcp --dport ${toString port} -m owner ! --uid-owner gerrit -j REJECT --reject-with tcp-reset";
      deleteRule = rule: "iptables -w -D ${rule} 2>/dev/null || true\n";
    in
    {
      networking.firewall = {
        extraCommands = deleteRule onlyGerritRule + "iptables -w -I ${onlyGerritRule}\n";
        extraStopCommands = deleteRule onlyGerritRule;
      };

      systemd.services.ci-trigger = {
        description = "Gerrit to Buildkite webhook receiver";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.openssh ];
        serviceConfig = {
          User = "buildkite-agent-main";
          Group = "buildkite-agent-main";
          Restart = "on-failure";
          UMask = "0077";
          NoNewPrivileges = true;
          CapabilityBoundingSet = "";
          ProtectSystem = "strict";
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
        environment = {
          PORT = toString port;
          BUILDKITE_REST_TOKEN_PATH = config.age.secrets.buildkite-rest-token.path;
          GERRIT_SSH_KEY_PATH = config.age.secrets.gerrit-ci-key.path;
          GERRIT_KNOWN_HOSTS_PATH = pkgs.writeText "gerrit-known-hosts" "${gerritKnownHosts}\n";
          GERRIT_SSH_DESTINATION = "buildkite@git.${domain}";
        };
        script = "exec ${pkgs.python3}/bin/python ${receiver}";
      };
    };
}
