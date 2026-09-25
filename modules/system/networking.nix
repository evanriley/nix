{ config, ... }:
let
  inherit (config.meta) user;
in
{
  flake.modules.nixos.networking = {
    networking.networkmanager.enable = true;
    networking.firewall.enable = true;

    services.tailscale.enable = true;
    services.tailscale.extraSetFlags = [ "--operator=${user.name}" ];

    programs.nm-applet.enable = true;
  };

  flake.modules.darwin.networking = {
    services.tailscale.enable = true;
  };
}
