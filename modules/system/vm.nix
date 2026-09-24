{ config, ... }:
let
  inherit (config.meta) user;
in
{
  flake.modules.nixos.vm =
    { lib, ... }:
    {
      virtualisation.vmVariant = {
        virtualisation = {
          memorySize = 8192;
          cores = 4;
          # No virgl: QEMU from nixpkgs cannot load a non-NixOS host's GL drivers.
          resolution = {
            x = 1920;
            y = 1080;
          };
        };

        boot.initrd.luks.devices = lib.mkForce { };

        users.users.${user.name} = {
          hashedPasswordFile = lib.mkForce null;
          password = "vm";
        };
      };
    };
}
