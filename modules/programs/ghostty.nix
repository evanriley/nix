{ config, ... }:
let
  inherit (config.flake.lib) monobiome;
  # Same slot mapping as foot's palette in modules/theme/theme.nix.
  theme = q: {
    background = "#${q.bg}";
    foreground = "#${q.fg_max}";
    cursor-color = "#${q.fg_bright}";
    cursor-text = "#${q.bg_alt}";
    selection-background = "#${q.bg_alt}";
    selection-foreground = "#${q.fg_bright}";
    palette = [
      "0=#${q.bg}"
      "1=#${q.red}"
      "2=#${q.green}"
      "3=#${q.yellow}"
      "4=#${q.blue}"
      "5=#${q.orange}"
      "6=#${q.blue}"
      "7=#${q.fg}"
      "8=#${q.selection}"
      "9=#${q.red_bright}"
      "10=#${q.green_bright}"
      "11=#${q.yellow_bright}"
      "12=#${q.blue_bright}"
      "13=#${q.orange_bright}"
      "14=#${q.blue_bright}"
      "15=#${q.fg_max}"
    ];
  };
in
{
  flake.modules.homeManager.ghostty =
    { pkgs, ... }:
    {
      programs.ghostty = {
        enable = true;
        # The source build is Linux-only; macOS uses the signed upstream app.
        package = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
        themes = {
          monobiome-dark = theme monobiome.dark;
          monobiome-light = theme monobiome.light;
        };
        settings = {
          # Follows the system appearance.
          theme = "light:monobiome-light,dark:monobiome-dark";
          font-family = "Berkeley Mono";
          font-size = 14;
          window-padding-x = 6;
          window-padding-y = 6;
          macos-option-as-alt = true;
        };
      };
    };
}
