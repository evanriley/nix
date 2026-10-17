{ lib, ... }:
{
  options.meta = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.anything;
    description = "Values shared by every configuration in this flake.";
  };

  config.meta = {
    user = {
      name = "evan";
      fullName = "Evan Riley";
      email = "evan@evanriley.com";
    };
    # Checkout location of the nix configuration flake, relative to the
    # home directory (/home/evan or /Users/evan).
    repoDir = "maybe/nix";
    # inputs.self carries the whole monorepo as string context, so secrets
    # are copied on their own to keep orca and manta out of every host.
    secrets = builtins.path {
      path = ../../secrets;
      name = "secrets";
    };
    projects =
      let
        registry = ../../../projects.json;
      in
      if builtins.pathExists registry then
        builtins.fromJSON (
          builtins.readFile (
            builtins.path {
              path = registry;
              name = "projects.json";
            }
          )
        )
      else
        throw "meta.projects reads projects.json at the maybe monorepo root, which this checkout lacks. Evaluate the flake from the monorepo (ssh://evan@git.maybemaybe.lol:29418/maybe), not the GitHub nix mirror";
    gerritKnownHosts = "[git.maybemaybe.lol]:29418 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHGOzrLcNC9G05r/TC3Gldb+gKLK+OZwmLN0xKVE2RIO";
    location = {
      latitude = 36.08;
      longitude = -78.91;
    };
  };
}
