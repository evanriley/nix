{ inputs, ... }:
{
  perSystem =
    {
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
      };

      packages = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        inherit (inputs.disko.packages.${system}) disko;
      };

      formatter = pkgs.nixfmt-tree;
    };
}
