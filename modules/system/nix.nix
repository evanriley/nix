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
      nix.gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };

      nixpkgs.config.allowUnfree = true;

      programs.nix-ld.enable = true;

      programs.nh.enable = true;
    };
}
