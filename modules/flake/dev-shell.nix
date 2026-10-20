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
        ++ lib.optional (system == "x86_64-linux") inputs.deploy-rs.packages.${system}.default
        ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.mkpasswd;
        shellHook = ''
          ${config.pre-commit.installationScript}
          if ${lib.getExe pkgs.gitMinimal} rev-parse --git-dir &>/dev/null; then
            ${lib.getExe pkgs.gitMinimal} config --local core.hooksPath \
              "$(${lib.getExe pkgs.gitMinimal} rev-parse --path-format=absolute --git-common-dir)/hooks"
          fi
        '';
      };

      formatter = pkgs.nixfmt-tree;
    };
}
