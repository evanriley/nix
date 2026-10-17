{
  perSystem =
    { config, pkgs, ... }:
    {
      packages.new-project = pkgs.writeShellApplication {
        name = "new-project";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnused
          pkgs.git
          pkgs.jq
          pkgs.gh
          pkgs.openssh
          pkgs.age
          pkgs.age-plugin-yubikey
        ];
        text = builtins.readFile ./_new-project.sh;
      };

      apps.new-project = {
        type = "app";
        program = "${config.packages.new-project}/bin/new-project";
      };

      checks.new-project = config.packages.new-project;
    };
}
