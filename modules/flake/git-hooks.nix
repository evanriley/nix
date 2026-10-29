{ inputs, ... }:
{
  imports = [ inputs.git-hooks.flakeModule ];

  perSystem =
    { lib, pkgs, ... }:
    let
      clangTools = pkgs.llvmPackages_latest.clang-tools;
    in
    {
      pre-commit.settings.rootSrc = lib.mkForce (
        builtins.path {
          path = ../..;
          name = "nix-source";
        }
      );
      pre-commit.settings.hooks.treefmt = {
        enable = true;
        packageOverrides.treefmt = pkgs.nixfmt-tree;
      };
      pre-commit.settings.hooks.clang-format = {
        enable = true;
        package = clangTools;
        entry = "${clangTools}/bin/clang-format --dry-run --Werror";
        files = "^orca2/.*\\.(cpp|hpp)$";
      };
    };
}
