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

      programs.zathura = {
        enable = true;
        options = {
          font = "Berkeley Mono 12";
          guioptions = "s";
          adjust-open = "best-fit";
          page-mode = "equal_width";
          pages-per-row = 1;
          scroll-step = 50;
          scroll-page-aware = true;
          scroll-full-overlap = 0.05;
          selection-clipboard = "clipboard";
          selection-notification = false;
          continuous-hist-save = true;
          database = "sqlite";
          statusbar-basename = true;
          statusbar-home-tilde = true;
          window-title-basename = true;
          window-title-home-tilde = true;
        };
        extraConfig = "include ${config.xdg.configHome}/theme/zathurarc";
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
        policies.DisableTelemetry = true;
        policies.DisableFirefoxStudies = true;
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
          # Written to user.js, which Firefox reapplies at every start.
          settings = {
            # userChrome.css is live-linked below and needs this to load.
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

            "browser.startup.page" = 3;
            "general.autoScroll" = true;
            "accessibility.typeaheadfind.flashBar" = 0;
            "dom.disable_open_during_load" = false;
            "media.eme.enabled" = true;
            "media.webspeech.synth.dont_notify_on_error" = true;
            "sidebar.revamp" = true;
            "sidebar.visibility" = "hide-on-close";
            "browser.bookmarks.showMobileBookmarks" = false;
            "browser.tabs.groups.smart.enabled" = false;
            "browser.translations.enable" = false;
            "pdfjs.enableAltText" = false;

            "browser.ai.control.default" = "blocked";
            "browser.ai.control.linkPreviewKeyPoints" = "blocked";
            "browser.ai.control.pdfjsAltText" = "blocked";
            "browser.ai.control.sidebarChatbot" = "blocked";
            "browser.ai.control.smartTabGroups" = "blocked";
            "browser.ai.control.smartWindow" = "blocked";
            "browser.ai.control.translations" = "blocked";
            "browser.smartwindow.memories.generateFromConversation" = false;
            "browser.smartwindow.memories.generateFromHistory" = false;
            "extensions.ml.enabled" = false;

            "browser.newtab.privateAllowed" = false;
            "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons" = false;
            "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features" = false;
            "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
            "browser.newtabpage.activity-stream.feeds.topsites" = false;
            "browser.newtabpage.activity-stream.hideLogo" = true;
            "browser.newtabpage.activity-stream.showSponsoredCheckboxes" = false;

            "browser.urlbar.showSearchSuggestionsFirst" = false;
            "browser.urlbar.suggest.engines" = false;
            "browser.urlbar.suggest.quicksuggest.all" = false;
            "browser.urlbar.suggest.searches" = false;
            "browser.urlbar.suggest.topsites" = false;
            "browser.urlbar.suggest.trending" = false;

            "browser.formfill.enable" = false;
            "extensions.formautofill.addresses.enabled" = false;
            "extensions.formautofill.creditCards.enabled" = false;
            "signon.rememberSignons" = false;
            "signon.generation.enabled" = false;
            "signon.firefoxRelay.feature" = "disabled";

            "browser.contentblocking.category" = "strict";
            "privacy.trackingprotection.enabled" = true;
            "privacy.trackingprotection.socialtracking.enabled" = true;
            "privacy.trackingprotection.emailtracking.enabled" = true;
            "privacy.trackingprotection.allow_list.convenience.enabled" = false;
            "privacy.trackingprotection.consentmanager.skip.pbmode.enabled" = false;
            "privacy.annotate_channels.strict_list.enabled" = true;
            "privacy.fingerprintingProtection" = true;
            "privacy.globalprivacycontrol.enabled" = true;
            "privacy.query_stripping.enabled" = true;
            "privacy.query_stripping.enabled.pbmode" = true;
            "privacy.history.custom" = true;
            "privacy.clearOnShutdown_v2.formdata" = true;
            "browser.safebrowsing.downloads.remote.block_potentially_unwanted" = false;
            "network.dns.disablePrefetch" = true;
            "network.prefetch-next" = false;
            "network.http.speculative-parallel-limit" = 0;

            "datareporting.healthreport.uploadEnabled" = false;
            "datareporting.usage.uploadEnabled" = false;
          };
        };
      };
      home.file = {
        "${profileDir}/chrome/userChrome.css".source = config.dotfiles.link "firefox/userChrome.css";
      };

      home.packages = with pkgs; [
        brave
        chromium
        discord
        # Font for the modernx OSC.
        mpvScripts.modernx
        yt-dlp
        swayimg
        nautilus
        pavucontrol
      ];
    };
}
