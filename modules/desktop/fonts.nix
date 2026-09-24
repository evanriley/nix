{
  flake.modules.nixos.fonts =
    { pkgs, ... }:
    {
      fonts.packages = with pkgs; [
        noto-fonts
        noto-fonts-color-emoji
        dejavu_fonts
        nerd-fonts.symbols-only
      ];
    };
}
