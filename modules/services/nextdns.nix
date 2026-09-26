let
  arguments = config: [
    "-config-file"
    config.age.secrets.nextdns.path
    "-report-client-info"
    "-cache-size"
    "10MB"
    "-listen"
    "localhost:53"
    "-forwarder"
    "ts.net=100.100.100.100"
  ];
  tailnet = "tailfe05b.ts.net";
  secret.file = ../../secrets/nextdns.conf.age;
in
{
  flake.modules.nixos.nextdns =
    { config, ... }:
    {
      age.secrets.nextdns = secret;

      services.nextdns = {
        enable = true;
        arguments = arguments config;
      };
      services.tailscale.extraSetFlags = [ "--accept-dns=false" ];

      networking.nameservers = [
        "127.0.0.1"
        "::1"
      ];
      networking.search = [ tailnet ];
      # Otherwise the router's resolver is added and lookups can bypass NextDNS.
      networking.networkmanager.dns = "none";
    };

  flake.modules.darwin.nextdns =
    { config, lib, ... }:
    {
      age.secrets.nextdns = secret;

      services.nextdns = {
        enable = true;
        arguments = arguments config ++ [ "-detect-captive-portals" ];
      };
      # Without this, nextdns can start before agenix at boot and run unfiltered.
      launchd.daemons.nextdns.serviceConfig = {
        RunAtLoad = lib.mkForce false;
        KeepAlive = lib.mkForce {
          PathState.${config.age.secrets.nextdns.path} = true;
        };
      };

      networking.knownNetworkServices = [ "Wi-Fi" ];
      networking.dns = [
        "127.0.0.1"
        "::1"
      ];
      networking.search = [ tailnet ];
    };
}
