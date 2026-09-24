{
  flake.modules.homeManager.apps =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        brave
        chromium
        firefox
        qutebrowser
        discord
        mpv
        yt-dlp
        swayimg
        zathura
        nautilus
        pavucontrol
        rbw
        pinentry-gnome3
      ];
    };
}
