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
        auto-optimise-store = true;
        extra-substituters = [ "https://devenv.cachix.org" ];
        extra-trusted-public-keys = [
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        ];
      };

      nixpkgs.config.allowUnfree = true;

      programs.nix-ld.enable = true;

      # Lix needs git for this flake before home-manager provides it.
      programs.git.enable = true;

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
