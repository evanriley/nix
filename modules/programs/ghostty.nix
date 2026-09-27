{ config, lib, ... }:
let
  inherit (config.flake.lib) monobiome;
  theme = q: {
    background = "#${q.bg}";
    foreground = "#${q.fg_max}";
    cursor-color = "#${q.fg_bright}";
    cursor-text = "#${q.bg_alt}";
    selection-background = "#${q.bg_alt}";
    selection-foreground = "#${q.fg_bright}";
    palette = lib.imap0 (index: color: "${toString index}=#${color}") (monobiome.ansi q);
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
