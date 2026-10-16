{ inputs, ... }:
{
  imports = [ inputs.git-hooks.flakeModule ];

  perSystem =
    { lib, pkgs, ... }:
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
    };
}
