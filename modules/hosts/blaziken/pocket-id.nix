{ config, ... }:
let
  inherit (config.meta) secrets;
  domain = "maybemaybe.lol";
  port = 1411;
in
{
  flake.modules.nixos.blaziken =
    { config, ... }:
    {
      age.secrets.pocket-id-key.file = secrets + "/blaziken/pocket-id-key.age";

      services.pocket-id = {
        enable = true;
        settings = {
          APP_URL = "https://id.${domain}";
          TRUST_PROXY = true;
          HOST = "127.0.0.1";
          PORT = toString port;
          ACTORS_HOST = "127.0.0.1";
          ACTORS_PORT = "1414";
          ANALYTICS_DISABLED = true;
        };
        credentials.ENCRYPTION_KEY = config.age.secrets.pocket-id-key.path;
      };

      systemd.services.pocket-id.restartTriggers = [
        (builtins.hashFile "sha256" config.age.secrets.pocket-id-key.file)
      ];

      services.nginx.virtualHosts."id.${domain}" = {
        forceSSL = true;
        useACMEHost = domain;
        locations."/".proxyPass = "http://127.0.0.1:${toString port}";
        # Until the first user exists, this endpoint makes anyone who calls it an admin.
        locations."= /api/signup/setup".return = "404";
      };
    };
}
