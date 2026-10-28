{ config, inputs, ... }:
let
  inherit (config.meta) secrets domain;
  port = 7200;
in
{
  flake.modules.nixos.blaziken =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      crosspointSync = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.crosspoint-sync;
      start = pkgs.writeShellScript "crosspoint-sync-start" ''
        TOKEN_ENC_KEY="$(<"$CREDENTIALS_DIRECTORY/token-enc-key")"
        export TOKEN_ENC_KEY
        exec ${lib.getExe crosspointSync}
      '';
    in
    {
      age.secrets.crosspoint-sync-key.file = secrets + "/blaziken/crosspoint-sync-key.age";

      systemd.services.crosspoint-sync = {
        description = "crosspoint-sync KOReader sync server";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        restartTriggers = [
          (builtins.hashFile "sha256" config.age.secrets.crosspoint-sync-key.file)
        ];
        environment = {
          NODE_ENV = "production";
          PORT = toString port;
          LISTEN_ADDRESS = "127.0.0.1";
          DATABASE_PATH = "/var/lib/crosspoint-sync/crosspoint.db";
          TRUST_PROXY = "true";
          WEB_APP_DIR = "${crosspointSync}/share/crosspoint-sync/web";
        };
        serviceConfig = {
          ExecStart = start;
          LoadCredential = "token-enc-key:${config.age.secrets.crosspoint-sync-key.path}";
          DynamicUser = true;
          StateDirectory = "crosspoint-sync";
          Restart = "on-failure";
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          NoNewPrivileges = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          ProtectHostname = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          RestrictNamespaces = true;
          RestrictSUIDSGID = true;
          RestrictRealtime = true;
          LockPersonality = true;
          UMask = "0077";
          CapabilityBoundingSet = "";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
          SystemCallFilter = [ "@system-service" ];
        };
      };

      services.nginx.virtualHosts."kosync.${domain}" = {
        forceSSL = true;
        useACMEHost = domain;
        locations."/".proxyPass = "http://127.0.0.1:${toString port}";
        # Registration happens through localhost only.
        locations."= /users/create".return = "404";
        locations."= /auth/signup".return = "404";
      };
    };
}
