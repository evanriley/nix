{
  perSystem =
    { config, pkgs, ... }:
    {
      packages.worktree = pkgs.writeShellApplication {
        name = "worktree";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
        ];
        text = builtins.readFile ./_worktree.sh;
      };

      apps.worktree = {
        type = "app";
        program = "${config.packages.worktree}/bin/worktree";
      };

      checks.worktree = config.packages.worktree;
    };
}
