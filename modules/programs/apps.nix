{
  flake.modules.homeManager.apps =
    { config, pkgs, ... }:
    let
      firefox = config.programs.firefox;
      profileDir = "${firefox.configPath}/${firefox.profiles.default.path}";
    in
    {
      dotfiles.config = [
        "mimeapps.list"
        "mpv"
        "qutebrowser"
        "rbw"
        "zathura"
      ];
      dotfiles.share = [
        "qutebrowser/greasemonkey"
        "qutebrowser/userscripts"
      ];

      programs.firefox = {
        enable = true;
        profiles.default = {
          id = 0;
          isDefault = true;
        };
      };
      home.file = {
        "${profileDir}/user.js".source = config.dotfiles.link "firefox/user.js";
        "${profileDir}/chrome/userChrome.css".source = config.dotfiles.link "firefox/userChrome.css";
        # Licensed font: not redistributable in this repository.
        ".local/share/fonts/berkeley-mono".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/sync/Fonts/Berkeley Mono";
      };

      home.packages = with pkgs; [
        brave
        chromium
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
