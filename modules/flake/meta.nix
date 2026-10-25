{ lib, ... }:
let
  domain = "pis.fyi";
in
{
  options.meta = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.anything;
    description = "Values shared by every configuration in this flake.";
  };

  config.meta = {
    inherit domain;
    user = {
      name = "evan";
      fullName = "Evan Riley";
      email = "evan@evanriley.com";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKvrBtmYXCnEIYTTlf1PjSkwrUU47CeNFEgq4hQ10vWi"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH3LxqQXhTWFxHLWjWfPgKsg79QAGBMdV+4DX/QBhV0X evan@ninetales"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIDUa51ANhGFP945U5rpjwK4q4YSj9v79pcUJkn5zlu5sAAAABHNzaDo= evan@cinderance yubikey-20477782 auth"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIK4PMbMXc6J5Vgah12OYp2jPRhAg47U0xssVS4kTphBAAAAABHNzaDo= evan@cinderance yubikey-20477902 auth"
      ];
    };
    hostKeys.cinderace = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIDES4qGRr0cZtmy1BQ0aO+5Ti1O+7Pyzk7O6XJnfuAI";
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
        throw "meta.projects reads projects.json at the maybe monorepo root, which this checkout lacks. Evaluate the flake from the monorepo (ssh://evan@git.${domain}:29418/maybe), not the GitHub nix mirror";
    gerritKnownHosts = "[git.${domain}]:29418 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHGOzrLcNC9G05r/TC3Gldb+gKLK+OZwmLN0xKVE2RIO";
    location = {
      latitude = 36.08;
      longitude = -78.91;
    };
  };
}
