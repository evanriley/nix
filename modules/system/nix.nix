{ config, ... }:
let
  inherit (config.meta) user repoDir;
  nixos = config.flake.modules.nixos;

  # Temporary: nixpkgs 55bfb4d builds lix 2.95.4 with -Dmimalloc, which
  # meson rejects on lix < 2.96 (fixed upstream in 982cb88083). Until the
  # channel advances, point the stable/latest aliases at lix 2.96.
  lixOverlay = _: prev: {
    lixPackageSets = prev.lixPackageSets // {
      inherit (prev.lixPackageSets) extend makeLixScope;
      latest = prev.lixPackageSets.lix_2_96;
      stable = prev.lixPackageSets.lix_2_96;
    };
  };
  settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    extra-substituters = [
      "https://evanriley.cachix.org"
      "https://devenv.cachix.org"
      "https://noctalia.cachix.org"
      "https://cache.numtide.com"
      "https://orca.cachix.org"
    ];
    extra-trusted-public-keys = [
      "evanriley.cachix.org-1:FnAK3k9mW9rdbrDHZduBUP5OqjmghMnwtbYzA1gbHdA="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "orca.cachix.org-1:Cn49KmT1A0Sg/RPfc6TnKmaQYirb2b58eZD6nUP/Nxg="
    ];
  };
in
{
  flake.modules.nixos.nix-core =
    { pkgs, ... }:
    {
      nixpkgs.overlays = [ lixOverlay ];
      nix.package = pkgs.lix;
      nix.channel.enable = false;
      nix.settings = settings // {
        auto-optimise-store = true;
        # deploy-rs copies closures over ssh as the wheel user.
        trusted-users = [
          "root"
          "@wheel"
        ];
      };
    };

  flake.modules.nixos.nix =
    { config, ... }:
    {
      imports = [ nixos.nix-core ];

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
      nixpkgs.overlays = [ lixOverlay ];
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
        # Apple's ssh lacks FIDO2 support for the YubiKey fallback keys.
        pkgs.openssh
      ];
      environment.variables.NH_FLAKE = "${config.users.users.${user.name}.home}/${repoDir}";
    };
}
