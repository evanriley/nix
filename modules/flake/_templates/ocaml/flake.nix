{
  description = "OCaml project";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, ... }:
    let
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (
          system: f nixpkgs.legacyPackages.${system}
        );
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.ocamlPackages.buildDunePackage {
          pname = "app";
          version = "0.1.0";
          src = ./.;
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          inputsFrom = [ self.packages.${pkgs.stdenv.hostPlatform.system}.default ];
          packages = [
            pkgs.ocamlPackages.ocaml-lsp
            pkgs.ocamlPackages.utop
            pkgs.ocamlformat
          ];
        };
      });

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
