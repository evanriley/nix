{
  flake.modules.homeManager.apps =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      firefox = config.programs.firefox;
      profileDir = "${firefox.configPath}/${firefox.profiles.default.path}";
    in
    {
      dotfiles.config = [
        "mpv"
        "zathura"
      ];

      programs.mpv = {
        enable = true;
        package = pkgs.mpv.override {
          scripts = with pkgs.mpvScripts; [
            modernx
            thumbfast
            sponsorblock
          ];
        };
      };

      programs.rbw = {
        enable = true;
        settings = {
          email = "evan@evanriley.com";
          lock_timeout = 43200;
          sync_interval = 900;
          pinentry = pkgs.pinentry-gnome3;
        };
      };

      xdg.mimeApps = {
        enable = true;
        defaultApplications =
          let
            web = [
              "x-scheme-handler/http"
              "x-scheme-handler/https"
              "x-scheme-handler/chrome"
              "text/html"
              "application/xhtml+xml"
              "application/x-extension-htm"
              "application/x-extension-html"
              "application/x-extension-shtml"
              "application/x-extension-xhtml"
              "application/x-extension-xht"
            ];
          in
          lib.genAttrs web (_: "firefox.desktop")
          // lib.genAttrs [ "image/png" "image/jpeg" "image/webp" ] (_: "swayimg.desktop")
          // {
            "application/pdf" = "org.pwmt.zathura-pdf-poppler.desktop";
            "inode/directory" = "org.gnome.Nautilus.desktop";
          };
      };

      programs.firefox = {
        enable = true;
        # Installed on first start and updated by Firefox; can be disabled, not removed.
        policies.ExtensionSettings =
          let
            amo = slug: "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
          in
          lib.mapAttrs
            (_: url: {
              installation_mode = "normal_installed";
              install_url = url;
            })
            {
              "{446900e4-71c2-419f-a6a7-df9c091e268b}" = amo "bitwarden-password-manager";
              "uBlock0@raymondhill.net" = amo "ublock-origin";
              "sponsorBlocker@ajay.app" = amo "sponsorblock";
              "deArrow@ajay.app" = amo "dearrow";
              "{762f9885-5a13-4abd-9c77-433dcd38b8fd}" = amo "return-youtube-dislikes";
              "enhancerforyoutube@maximerf.addons.mozilla.org" = amo "enhancer-for-youtube";
              "{9063c2e9-e07c-4c2c-9646-cfe7ca8d0498}" = amo "old-reddit-redirect";
              "{278b0ae0-da9d-4cc6-be81-5aa7f3202672}" = amo "re-enable-right-click";
              "search@kagi.com" = amo "kagi-search-for-firefox";
              "browser-extension@anonaddy" = amo "addy_io";
              "ntsplusextension@gmail.com" = amo "nts-plus";
              "{326783cf-14a4-495f-b010-dc9481919dd5}" = amo "monobiome-alpine";
              "tridactyl.vim.betas@cmcaine.co.uk" = "https://tridactyl.cmcaine.co.uk/betas/tridactyl-latest.xpi";
            };
        profiles.default = {
          id = 0;
          isDefault = true;
          # userChrome.css is live-linked below and needs this to load.
          settings."toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        };
      };
      home.file = {
        "${profileDir}/chrome/userChrome.css".source = config.dotfiles.link "firefox/userChrome.css";
        # Licensed font: not redistributable in this repository.
        ".local/share/fonts/berkeley-mono".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/sync/Fonts/Berkeley Mono";
      };

      home.packages = with pkgs; [
        brave
        chromium
        discord
        # Font for the modernx OSC.
        mpvScripts.modernx
        yt-dlp
        swayimg
        zathura
        nautilus
        pavucontrol
      ];
    };
}
