{ config, ... }:
let
  inherit (config.meta) domain;
  oauth2ProxyPort = 4181;
  oauth2ProxyClientSecret = "/run/oauth2-proxy-rspamd/client-secret";
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
      mainProxy = config.services.oauth2-proxy;
      oauth2ProxyAddress = "127.0.0.1:${toString oauth2ProxyPort}";
      authenticatedEmails = pkgs.writeText "authenticated-emails" mainProxy.email.addresses;
      oauth2ProxyFlags = [
        "--provider=${mainProxy.provider}"
        "--oidc-issuer-url=${mainProxy.oidcIssuerUrl}"
        "--client-id=${mainProxy.clientID}"
        "--client-secret-file=${oauth2ProxyClientSecret}"
        "--cookie-secret-file=%d/cookie-secret"
        "--redirect-url=https://rspamd.${domain}/oauth2/callback"
        "--proxy-prefix=${mainProxy.proxyPrefix}"
        "--http-address=http://${oauth2ProxyAddress}"
        "--cookie-name=${mainProxy.cookie.name}"
        "--cookie-expire=${mainProxy.cookie.expire}"
        "--cookie-secure=${lib.boolToString mainProxy.cookie.secure}"
        "--cookie-httponly=${lib.boolToString mainProxy.cookie.httpOnly}"
        "--authenticated-emails-file=${authenticatedEmails}"
        "--approval-prompt=${mainProxy.approvalPrompt}"
        "--reverse-proxy=${lib.boolToString mainProxy.reverseProxy}"
        "--pass-access-token=${lib.boolToString mainProxy.passAccessToken}"
        "--pass-basic-auth=${lib.boolToString mainProxy.passBasicAuth}"
        "--pass-host-header=${lib.boolToString mainProxy.passHostHeader}"
        "--set-xauthrequest=${lib.boolToString mainProxy.setXauthrequest}"
        "--request-logging=${lib.boolToString mainProxy.requestLogging}"
      ]
      ++ map (ip: "--trusted-proxy-ip=${ip}") mainProxy.trustedProxyIP;
    in
    {
      services.nginx.virtualHosts."rspamd.${domain}" = {
        forceSSL = true;
        useACMEHost = domain;
        locations."/" = {
          proxyPass = "http://unix:/run/rspamd/worker-controller.sock:/";
          recommendedProxySettings = false;
          extraConfig = ''
            proxy_set_header X-Forwarded-For "";
            proxy_set_header X-Real-IP "";
            auth_request /oauth2/auth;
            error_page 401 = @redirectToOauth2Login;
          '';
        };
        locations."/oauth2/" = {
          proxyPass = "http://${oauth2ProxyAddress}";
          extraConfig = ''
            auth_request off;
            proxy_set_header X-Scheme                $scheme;
            proxy_set_header X-Auth-Request-Redirect $scheme://$host$request_uri;
          '';
        };
        locations."= /oauth2/auth" = {
          proxyPass = "http://${oauth2ProxyAddress}/oauth2/auth";
          extraConfig = ''
            auth_request off;
            proxy_set_header X-Scheme         $scheme;
            proxy_set_header Content-Length   "";
            proxy_pass_request_body           off;
          '';
        };
        locations."@redirectToOauth2Login" = {
          return = "307 /oauth2/start?rd=$request_uri";
          extraConfig = ''
            auth_request off;
          '';
        };
      };

      systemd.services.oauth2-proxy-rspamd = {
        description = "OAuth2 Proxy for rspamd";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
          "nginx.service"
          "pocket-id.service"
        ];
        wants = [
          "network-online.target"
          "nginx.service"
          "pocket-id.service"
        ];
        startLimitIntervalSec = 0;
        serviceConfig = {
          User = "oauth2-proxy";
          Group = "oauth2-proxy";
          ExecStart = "${lib.getExe mainProxy.package} ${lib.escapeShellArgs oauth2ProxyFlags}";
          Restart = "always";
          RestartSec = "5s";
          RuntimeDirectory = "oauth2-proxy-rspamd";
          RuntimeDirectoryMode = "700";
          LoadCredential = [
            "git-bug-oidc-secret:${config.age.secrets.git-bug-oidc-secret.path}"
            "cookie-secret:${config.age.secrets.oauth2-proxy-cookie-secret.path}"
          ];
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
        # oauth2-proxy sends the client secret file verbatim, trailing newline
        # included.
        preStart = ''
          oidc_secret="$(< "$CREDENTIALS_DIRECTORY/git-bug-oidc-secret")"
          if [[ ! "$oidc_secret" =~ ^[A-Za-z0-9]+$ ]]; then
            echo "${config.age.secrets.git-bug-oidc-secret.path} is not an alphanumeric client secret; expected the secret Pocket ID shows for the git-bug client. Re-encrypt git-bug-oidc-secret.age with it." >&2
            exit 1
          fi
          umask 077
          printf '%s' "$oidc_secret" > ${oauth2ProxyClientSecret}
        '';
        restartTriggers = [
          (builtins.hashFile "sha256" config.age.secrets.git-bug-oidc-secret.file)
          (builtins.hashFile "sha256" config.age.secrets.oauth2-proxy-cookie-secret.file)
        ];
      };
    };
}
