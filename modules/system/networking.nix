{ config, ... }:
let
  inherit (config.meta) user;
in
{
  flake.modules.nixos.networking = {
    networking.firewall.enable = true;

    services.tailscale.enable = true;
    services.tailscale.extraSetFlags = [ "--operator=${user.name}" ];

    services.borgmatic.configurations.home.source_directories = [ "/var/lib/tailscale" ];
  };

  flake.modules.darwin.networking = {
    homebrew.casks = [ "tailscale-app" ];
  };
}
