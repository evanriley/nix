{ config, inputs, ... }:
let
  nixos = config.flake.modules.nixos;
in
{
  flake.nixosConfigurations.ci-builder = inputs.nixpkgs.lib.nixosSystem {
    modules = [ nixos.ci-builder ];
  };

  flake.modules.nixos.ci-builder =
    { lib, modulesPath, ... }:
    {
      imports = [
        "${modulesPath}/virtualisation/google-compute-image.nix"
        nixos.ci-builder-agent
      ];

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
      services.openssh.enable = lib.mkForce false;

      users.mutableUsers = false;
      users.allowNoPasswordLogin = true;
    };
}
