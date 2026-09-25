{ inputs, ... }:
{
  perSystem =
    {
      config,
      pkgs,
      lib,
      system,
      ...
    }:
    {
      devShells.default = pkgs.mkShellNoCC {
        packages = [
          inputs.agenix.packages.${system}.default
          pkgs.age
          pkgs.age-plugin-yubikey
          pkgs.nixfmt
        ]
        ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.mkpasswd;
        shellHook = config.pre-commit.installationScript;
      };

      formatter = pkgs.nixfmt-tree;
    };
}
