{
  config,
  inputs,
  lib,
  ...
}:
{
  flake.deploy = {
    sshUser = "evan";
    nodes.blaziken = {
      # Admin plane runs over Tailscale, independent of public DNS.
      hostname = "100.84.202.88";
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos config.flake.nixosConfigurations.blaziken;
      };
    };
  };

  perSystem =
    { system, ... }:
    lib.mkIf (system == "x86_64-linux") {
      checks = inputs.deploy-rs.lib.${system}.deployChecks config.flake.deploy;
    };
}
