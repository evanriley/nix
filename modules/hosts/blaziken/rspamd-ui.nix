{ config, ... }:
let
  inherit (config.meta) domain;
in
{
  flake.modules.nixos.blaziken = {
    services.nginx.virtualHosts."rspamd.${domain}" = {
      forceSSL = true;
      useACMEHost = domain;
      locations."/" = {
        proxyPass = "http://unix:/run/rspamd/worker-controller.sock:/";
        recommendedProxySettings = false;
        extraConfig = ''
          proxy_set_header X-Forwarded-For "";
          proxy_set_header X-Real-IP "";
        '';
      };
    };

    services.oauth2-proxy.nginx.virtualHosts."rspamd.${domain}" = { };
  };
}
