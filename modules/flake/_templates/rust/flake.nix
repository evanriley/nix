{
  description = "Rust project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
      ...
    }:
    let
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (
          system: f nixpkgs.legacyPackages.${system}
        );
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          craneLib = crane.mkLib pkgs;
        in
        {
          default = craneLib.buildPackage {
            src = craneLib.cleanCargoSource ./.;
            strictDeps = true;
          };
        }
      );

      devShells = forAllSystems (pkgs: {
        default = (crane.mkLib pkgs).devShell {
          packages = [
            pkgs.clippy
            pkgs.rustfmt
            pkgs.rust-analyzer
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
