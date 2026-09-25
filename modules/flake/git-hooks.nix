{ inputs, ... }:
{
  imports = [ inputs.git-hooks.flakeModule ];

  # Installed into .git/hooks by the dev shell; also runs as checks.pre-commit.
  perSystem =
    { pkgs, ... }:
    {
      pre-commit.settings.hooks.treefmt = {
        enable = true;
        packageOverrides.treefmt = pkgs.nixfmt-tree;
      };
    };
}
