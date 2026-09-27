{
  flake.modules.homeManager.apps =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      programs.zathura = {
        enable = true;
        options = {
          font = "${config.stylix.fonts.monospace.name} 12";
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

      home.packages = with pkgs; [
        brave
        (chromium.override { enableWideVine = true; })
        swayimg
        nautilus
        pavucontrol
      ];
    };
}
