{
  description = "Clojure project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    clj-nix = {
      url = "github:jlesquembre/clj-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      clj-nix,
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
      # Needs deps-lock.json: run `deps-lock` after changing deps.edn.
      packages = forAllSystems (
        system: pkgs: {
          default = clj-nix.lib.mkCljApp {
            inherit pkgs;
            modules = [
              {
                projectSrc = ./.;
                name = "app/app";
                main-ns = "app.core";
              }
            ];
          };
        }
      );

      devShells = forAllSystems (
        system: pkgs: {
          default = pkgs.mkShell {
            packages = [
              pkgs.clojure
              pkgs.clojure-lsp
              pkgs.clj-kondo
              pkgs.babashka
              clj-nix.packages.${system}.deps-lock
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
