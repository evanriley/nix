{
  flake.modules.nixos.navidrome =
    { config, lib, ... }:
    let
      inherit (config.services.navidrome.settings) Address Port;
      tailscale = lib.getExe config.services.tailscale.package;
    in
    {
      services.navidrome = {
        enable = true;
        settings.MusicFolder = "/data/Music";
      };
      systemd.services.navidrome.unitConfig.RequiresMountsFor = [ "/data" ];

      # HTTPS on the tailnet at https://<host>.<tailnet>.ts.net:<Port>.
      systemd.services.navidrome-tailscale-serve = {
        description = "Serve Navidrome on the tailnet";
        after = [
          "tailscaled.service"
          "navidrome.service"
        ];
        wants = [ "tailscaled.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${tailscale} serve --bg --https=${toString Port} http://${Address}:${toString Port}";
          ExecStop = "${tailscale} serve --https=${toString Port} off";
          # tailscaled refuses serve until it has logged in.
          Restart = "on-failure";
          RestartSec = 10;
        };
      };

      services.borgmatic.configurations.home = {
        source_directories = [ "/var/lib/navidrome" ];
        sqlite_databases = [
          {
            name = "navidrome";
            path = "/var/lib/navidrome/navidrome.db";
          }
        ];
        exclude_patterns = [
          "sh:/var/lib/navidrome/navidrome.db*"
          "/var/lib/navidrome/cache"
        ];
      };
    };
}
