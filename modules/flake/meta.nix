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
    repo = "/home/evan/nix";
  };
}
