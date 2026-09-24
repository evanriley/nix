{ config, inputs, ... }:
let
  inherit (config.meta) repo;
in
{
  flake.modules.homeManager.dotfiles =
    { config, lib, ... }:
    let
      link =
        path:
        if config.dotfiles.mutable then
          config.lib.file.mkOutOfStoreSymlink "${repo}/home/${path}"
        else
          inputs.self + "/home/${path}";

      configEntries = [
        "btop"
        "darkman"
        "direnv"
        "fastfetch"
        "fish"
        "foot"
        "fuzzel"
        "git"
        "gtk-3.0"
        "gtk-4.0"
        "kak"
        "listenbrainz-mpd"
        "mimeapps.list"
        "mpd"
        "mpv"
        "niri"
        "nvim"
        "pipewire"
        "qutebrowser"
        "rbw"
        "rmpc"
        "scapectl"
        "scripts"
        "swaync"
        "swayosd"
        "tmux"
        "waybar"
        "wireplumber"
        "xdg-desktop-portal"
        "yubikey-touch-detector"
        "zathura"
      ];

      scripts = [
        "desktopctl"
        "display-mode"
        "git-ssh-keygen"
      ];

      firefoxProfile = ".config/mozilla/firefox/b437d468.default-release";
    in
    {
      options.dotfiles.mutable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Link dotfiles to the live checkout instead of the Nix store.";
      };

      config = {
        xdg.configFile = lib.genAttrs configEntries (name: {
          source = link "config/${name}";
        });

        home.file =
          lib.genAttrs (map (name: ".local/bin/${name}") scripts) (path: {
            source = link "bin/${baseNameOf path}";
          })
          // {
            ".local/share/darkman".source = link "share/darkman";
            ".local/share/qutebrowser/greasemonkey".source = link "share/qutebrowser/greasemonkey";
            ".local/share/qutebrowser/userscripts".source = link "share/qutebrowser/userscripts";
            "${firefoxProfile}/user.js".source = link "firefox/user.js";
            "${firefoxProfile}/chrome/userChrome.css".source = link "firefox/userChrome.css";
            # Licensed font: not redistributable in this repository.
            ".local/share/fonts/berkeley-mono".source =
              config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/sync/Fonts/Berkeley Mono";
          };

        home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];
      };
    };
}
