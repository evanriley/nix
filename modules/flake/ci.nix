{ config, lib, ... }:
let
  inherit (config.flake) nixosConfigurations darwinConfigurations homeConfigurations;
  toplevel = host: nixosConfigurations.${host}.config.system.build.toplevel;
in
{
  meta.buildkiteJobPackages = pkgs: nix: [
    pkgs.bash
    pkgs.git
    pkgs.curl
    pkgs.jq
    pkgs.josh
    pkgs.openssh
    pkgs.lixPackageSets.stable.nix-eval-jobs
    nix
  ];

  perSystem =
    { config, system, ... }:
    let
      buildsHere = _: home: home.pkgs.stdenv.hostPlatform.system == system;
      activationPackages = lib.mapAttrs (_: home: home.activationPackage);
    in
    lib.mkIf (system == "x86_64-linux") {
      legacyPackages.ci = {
        targets =
          lib.mapAttrs' (name: lib.nameValuePair "checks.${name}") config.checks
          // activationPackages (lib.filterAttrs buildsHere homeConfigurations)
          // {
            cinderace = toplevel "cinderace";
            blaziken = toplevel "blaziken";
            ci-builder = toplevel "ci-builder";
          };
        evalOnly =
          activationPackages (lib.filterAttrs (name: home: !buildsHere name home) homeConfigurations)
          // {
            ninetales = darwinConfigurations.ninetales.system;
          };
        extraSteps = [ ];
        fullSteps = [ ];
      };
    };
}
