{
  description = "C++ project";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      forAllSystems =
        f: lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (system: f nixpkgs.legacyPackages.${system});
      source = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.difference ./. (
          lib.fileset.unions [
            (lib.fileset.fileFilter (file: file.hasExt "md") ./.)
            (lib.fileset.maybeMissing ./build)
          ]
        );
      };
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.llvmPackages_latest.stdenv.mkDerivation {
          pname = "app";
          version = "0.1.0";
          src = source;
          nativeBuildInputs = [
            pkgs.cmake
            pkgs.ninja
          ];
          checkInputs = [ pkgs.catch2_3 ];
          doCheck = true;
        };
      });

      devShells = forAllSystems (
        pkgs:
        let
          llvm = pkgs.llvmPackages_latest;
        in
        {
          default = (pkgs.mkShell.override { stdenv = llvm.stdenv; }) {
            inputsFrom = [ self.packages.${pkgs.stdenv.hostPlatform.system}.default ];
            packages = [
              llvm.clang-tools
              llvm.lldb
              llvm.llvm
            ];
            hardeningDisable = [
              "fortify"
              "libcxxhardeningfast"
            ];
          };
        }
      );

      legacyPackages.x86_64-linux.ci =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
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
