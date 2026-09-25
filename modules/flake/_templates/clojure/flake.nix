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
    { nixpkgs, clj-nix, ... }:
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
    };
}
