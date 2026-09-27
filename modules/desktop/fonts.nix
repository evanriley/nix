{ config, ... }:
let
  inherit (config.flake.lib) berkeleyMono;
in
{
  flake.modules.nixos.fonts =
    { pkgs, ... }:
    {
      fonts.packages = with pkgs; [
        (berkeleyMono pkgs)
        noto-fonts
        noto-fonts-color-emoji
        dejavu_fonts
        nerd-fonts.symbols-only
      ];
    };
}
