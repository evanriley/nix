{ inputs, ... }:
{
  imports = [ inputs.git-hooks.flakeModule ];

  perSystem =
    { pkgs, ... }:
    {
      pre-commit.settings.hooks.treefmt = {
        enable = true;
        packageOverrides.treefmt = pkgs.nixfmt-tree;
      };
    };
}
