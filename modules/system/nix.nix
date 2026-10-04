{ config, ... }:
let
  inherit (config.meta) user repoDir;
  settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    extra-substituters = [
      "https://devenv.cachix.org"
      "https://noctalia.cachix.org"
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };
in
{
  flake.modules.nixos.nix =
    { config, pkgs, ... }:
    {
      nix.package = pkgs.lix;
      nix.channel.enable = false;
      nix.settings = settings // {
        auto-optimise-store = true;
      };

      nixpkgs.config.allowUnfree = true;

      programs.nix-ld.enable = true;

      # Lix needs git for this flake before home-manager provides it.
      programs.git.enable = true;

      programs.nh = {
        enable = true;
        flake = "${config.users.users.${user.name}.home}/${repoDir}";
        # Also collects home-manager generations, which theme switches create.
        clean = {
          enable = true;
          dates = "weekly";
          extraArgs = "--keep-since 30d --keep 5";
        };
      };
    };

  flake.modules.darwin.nix =
    { config, pkgs, ... }:
    {
      nix.package = pkgs.lix;
      nix.channel.enable = false;
      nix.settings = settings;
      # auto-optimise-store is unreliable on macOS; optimise on a schedule instead.
      nix.optimise.automatic = true;
      nix.gc = {
        automatic = true;
        options = "--delete-older-than 30d";
      };

      nixpkgs.config.allowUnfree = true;

      environment.systemPackages = [
        pkgs.git
        pkgs.nh
        # Apple's ssh lacks FIDO2 support; the YubiKey keys fetch private inputs.
        pkgs.openssh
      ];
      environment.variables.NH_FLAKE = "${config.users.users.${user.name}.home}/${repoDir}";
    };
}
