{ config, ... }:
let
  inherit (config.meta) secrets domain;
  port = 5232;
in
{
  flake.modules.nixos.blaziken =
    { config, ... }:
    {
      age.secrets.rustical-env.file = secrets + "/blaziken/rustical.env.age";

      services.rustical = {
        enable = true;
        environmentFiles = [ config.age.secrets.rustical-env.path ];
        settings = {
          http.bind = "127.0.0.1:${toString port}";
          frontend.allow_password_login = false;
          oidc = {
            name = "Pocket ID";
            issuer = "https://id.${domain}";
            client_id = "b83068b5-74f0-43cb-bd3b-8329ed8a7430";
            claim_userid = "preferred_username";
            scopes = [
              "openid"
              "profile"
            ];
            allow_sign_up = true;
          };
        };
      };

      systemd.services.rustical.restartTriggers = [
        (builtins.hashFile "sha256" config.age.secrets.rustical-env.file)
      ];

      services.nginx.virtualHosts."dav.${domain}" = {
        forceSSL = true;
        useACMEHost = domain;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString port}";
          extraConfig = "client_max_body_size 50m;";
        };
      };
    };
}
