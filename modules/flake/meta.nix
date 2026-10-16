{ lib, ... }:
{
  options.meta = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
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
    location = {
      latitude = 36.08;
      longitude = -78.91;
    };
  };
}
