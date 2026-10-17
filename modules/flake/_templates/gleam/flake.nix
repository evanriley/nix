{
  description = "Gleam project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-gleam = {
      url = "github:arnarg/nix-gleam";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-gleam,
      ...
    }:
    let
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (
          system: f system nixpkgs.legacyPackages.${system}
        );
    in
    {
      packages = forAllSystems (
        system: pkgs: {
          default = nix-gleam.packages.${system}.buildGleamApplication { src = ./.; };
        }
      );

      devShells = forAllSystems (
        system: pkgs: {
          default = pkgs.mkShell {
            packages = [
              pkgs.gleam
              pkgs.beamPackages.erlang
              pkgs.beamPackages.rebar3
            ];
          };
        }
      );

      legacyPackages.x86_64-linux.ci =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          source = nixpkgs.lib.fileset.toSource {
            root = ./.;
            fileset = nixpkgs.lib.fileset.difference ./. (
              nixpkgs.lib.fileset.fileFilter (file: file.hasExt "md") ./.
            );
          };
          step = key: label: command: {
            inherit key label command;
            target = "source";
          };
        in
        {
          targets = {
            package = self.packages.x86_64-linux.default;
            source = pkgs.runCommandLocal "app-source" { } "ln -s ${source} $out";
          };
          evalOnly = { };
          extraSteps = [
            (step "app-fmt" "app: fmt" "app/ci.sh fmt")
            (step "app-test" "app: test" "app/ci.sh test" // { depends_on = [ "app-fmt" ]; })
          ];
          fullSteps = [ ];
        };
    };
}
