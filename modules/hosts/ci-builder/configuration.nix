{ config, inputs, ... }:
let
  nixos = config.flake.modules.nixos;
in
{
  flake.nixosConfigurations.ci-builder = inputs.nixpkgs.lib.nixosSystem {
    modules = [ nixos.ci-builder ];
  };

  flake.modules.nixos.ci-builder =
    { lib, ... }:
    {
      imports = [
        nixos.ci-builder-image
        nixos.ci-builder-agent
      ];

      services.openssh.enable = lib.mkForce false;
    };

  flake.modules.nixos.ci-builder-image =
    { lib, modulesPath, ... }:
    {
      imports = [ "${modulesPath}/virtualisation/google-compute-image.nix" ];

      system.stateVersion = "26.11";
      nixpkgs.hostPlatform = "x86_64-linux";

      virtualisation.googleComputeImage.efi = true;
      virtualisation.diskSize = 8 * 1024;
      boot.kernelModules = [ "gve" ];

      systemd.services = {
        google-guest-agent.enable = false;
        google-startup-scripts.enable = false;
        google-shutdown-scripts.enable = false;
      };
      security.googleOsLogin.enable = lib.mkForce false;

      users.mutableUsers = false;
      users.allowNoPasswordLogin = true;
    };
}
