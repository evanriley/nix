{ config, ... }:
let
  inherit (config.meta) user;
in
{
  flake.modules.nixos.networking = {
    networking.firewall.enable = true;

    services.tailscale.enable = true;
    services.tailscale.extraSetFlags = [ "--operator=${user.name}" ];
  };

  flake.modules.darwin.networking = {
    homebrew.casks = [ "tailscale-app" ];
  };
}
