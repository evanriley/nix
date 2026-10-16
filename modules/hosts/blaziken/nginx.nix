{
  config,
  inputs,
  ...
}:
let
  inherit (config.meta) user;
  domain = "maybemaybe.lol";
in
{
  flake.modules.nixos.blaziken =
    { config, ... }:
    {
      services.anubis.instances.homepage = {
        # nginx needs to reach the challenge proxy's unix socket.
        group = "nginx";
        settings.TARGET = "http://127.0.0.1:8080";
      };

      services.nginx = {
        enable = true;
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;

        virtualHosts.homepage-upstream = {
          serverName = "homepage-upstream";
          # Anubis proxies here after clearing the challenge.
          listen = [
            {
              addr = "127.0.0.1";
              port = 8080;
            }
          ];
          root = ./homepage;
          locations."/" = {
            tryFiles = "$uri $uri/ =404";
          };
        };

        virtualHosts."www.${domain}" = {
          forceSSL = true;
          useACMEHost = domain;
          globalRedirect = domain;
        };

        virtualHosts.${domain} = {
          forceSSL = true;
          useACMEHost = domain;
          locations."/" = {
            proxyPass = "http://unix:/run/anubis/anubis-homepage/anubis.sock";
          };
        };
      };

      security.acme = {
        acceptTerms = true;
        defaults.email = user.email;
        certs.${domain} = {
          group = "nginx";
          dnsProvider = "cloudflare";
          # Tailscale MagicDNS is the system resolver and does not return
          # ACME TXT records; query public resolvers directly.
          dnsResolver = "1.1.1.1:53,9.9.9.9:53";
          environmentFile = config.age.secrets.cloudflare-dns.path;
          extraDomainNames = [ "*.${domain}" ];
        };
      };

      age.secrets.cloudflare-dns = {
        file = inputs.self + "/secrets/blaziken/cloudflare-dns.age";
        owner = "acme";
      };
    };
}
