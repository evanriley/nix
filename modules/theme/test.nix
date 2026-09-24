{ config, inputs, ... }:
let
  inherit (config.meta) user;
  homeManager = config.flake.modules.homeManager;
in
{
  # Activates the home configuration, then switches light -> dark -> light
  # with apply-theme, the way darkman does at sunrise and sunset.
  perSystem =
    { pkgs, system, ... }:
    inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
      checks.theme-switch = pkgs.testers.runNixOSTest {
        name = "theme-switch";
        nodes.machine = {
          imports = [ inputs.home-manager.nixosModules.home-manager ];
          users.users.${user.name}.isNormalUser = true;
          programs.dconf.enable = true;
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.${user.name} = {
              imports = with homeManager; [
                base
                dotfiles
                theme
              ];
              dotfiles.mutable = false;
              # Keeps the test independent of the private berkeley-mono input (CI has no access).
              stylix.fonts.monospace = pkgs.lib.mkForce {
                name = "DejaVu Sans Mono";
                package = pkgs.dejavu_fonts;
              };
            };
          };
          virtualisation.memorySize = 2048;
        };
        testScript = ''
          machine.wait_for_unit("home-manager-${user.name}.service")

          def as_user(command):
              return machine.succeed(f"su - ${user.name} -c '{command}'").strip()

          def assert_mode(mode, bg):
              assert as_user("cat ~/.config/theme/mode") == mode
              assert f"color={bg}" in as_user("cat ~/.config/swaylock/config")
              assert as_user("readlink -f ~/.config/theme/foot.ini") != ""

          with subtest("base generation is dark and records itself"):
              assert_mode("dark", "262626")
              as_user("test -L ~/.local/state/theme/base")

          with subtest("switch to light"):
              as_user("apply-theme light")
              assert_mode("light", "f5f5f5")

          with subtest("switch back to dark from the light generation"):
              as_user("apply-theme dark")
              assert_mode("dark", "262626")

          with subtest("switch to light again"):
              as_user("apply-theme light")
              assert_mode("light", "f5f5f5")
        '';
      };
    };
}
