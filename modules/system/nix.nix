{ config, ... }:
let
  inherit (config.meta) repo;
in
{
  flake.modules.nixos.nix =
    { pkgs, ... }:
    {
      nix.package = pkgs.lix;
      nix.channel.enable = false;
      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        trusted-users = [
          "root"
          "@wheel"
        ];
        auto-optimise-store = true;
      };

      nixpkgs.config.allowUnfree = true;

      programs.nix-ld.enable = true;

      programs.nh = {
        enable = true;
        flake = repo;
        # Also collects home-manager generations, which theme switches create.
        clean = {
          enable = true;
          dates = "weekly";
          extraArgs = "--keep-since 30d --keep 5";
        };
      };
    };
}
