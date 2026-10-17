{ config, lib, ... }:
let
  inherit (config.flake) nixosConfigurations darwinConfigurations homeConfigurations;
  toplevel = host: nixosConfigurations.${host}.config.system.build.toplevel;
in
{
  perSystem =
    { config, system, ... }:
    lib.mkIf (system == "x86_64-linux") {
      legacyPackages.ci = {
        targets = lib.mapAttrs' (name: lib.nameValuePair "checks.${name}") config.checks // {
          cinderace = toplevel "cinderace";
          blaziken = toplevel "blaziken";
        };
        evalOnly = lib.mapAttrs (_: home: home.activationPackage) homeConfigurations // {
          ninetales = darwinConfigurations.ninetales.system;
        };
        extraSteps = [ ];
        fullSteps = [ ];
      };
    };
}
