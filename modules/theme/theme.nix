{ config, inputs, ... }:
let
  inherit (config.flake.lib) monobiome;
in
{
  # Hand-written configs in home/config include the generated files under
  # ~/.config/theme instead of carrying colors themselves.
  flake.modules.homeManager.theme =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.theme) mode;
      isLinux = pkgs.stdenv.hostPlatform.isLinux;
      p = monobiome.${mode};
      monospace = config.stylix.fonts.monospace.name;
      themeDir = "${config.xdg.configHome}/theme";
      baseLink = "${config.xdg.stateHome}/theme/base";

      # Restores Inherits=AdwaitaLegacy, which nixpkgs drops; legacy icon names break without it.
      adwaitaIcons = pkgs.adwaita-icon-theme.overrideAttrs {
        postPatch = ''
          substituteInPlace index.theme --replace-fail "Hidden=true" ""
        '';
      };

      footColors =
        name: q:
        let
          slots = lib.imap0 (
            index: color:
            if index < 8 then "regular${toString index}=${color}" else "bright${toString (index - 8)}=${color}"
          ) (monobiome.ansi q);
        in
        ''
          [colors-${name}]
          foreground=${q.fg_max}
          background=${q.bg}
          selection-foreground=${q.fg_bright}
          selection-background=${q.bg_alt}
          urls=${q.blue}
          cursor=${q.bg_alt} ${q.fg_bright}
          ${lib.concatStringsSep "\n" slots}
        '';

      noctaliaPalette =
        q:
        let
          ansi = map (color: "#${color}") (monobiome.ansi q);
          names = [
            "black"
            "red"
            "green"
            "yellow"
            "blue"
            "magenta"
            "cyan"
            "white"
          ];
          slots =
            offset:
            lib.listToAttrs (
              lib.imap0 (index: name: lib.nameValuePair name (lib.elemAt ansi (index + offset))) names
            );
        in
        {
          mPrimary = "#${q.blue}";
          mOnPrimary = "#${q.bg}";
          mSecondary = "#${q.orange}";
          mOnSecondary = "#${q.bg}";
          mTertiary = "#${q.green}";
          mOnTertiary = "#${q.bg}";
          mError = "#${q.red}";
          mOnError = "#${q.bg}";
          mSurface = "#${q.bg}";
          mOnSurface = "#${q.fg_max}";
          mSurfaceVariant = "#${q.bg_alt}";
          mOnSurfaceVariant = "#${q.fg}";
          mOutline = "#${q.border}";
          mShadow = "#${q.bg}";
          mHover = "#${q.selection}";
          mOnHover = "#${q.fg_max}";
          terminal = {
            background = "#${q.bg}";
            foreground = "#${q.fg_max}";
            cursor = "#${q.fg_bright}";
            cursorText = "#${q.bg_alt}";
            selectionBg = "#${q.bg_alt}";
            selectionFg = "#${q.fg_bright}";
            normal = slots 0;
            bright = slots 8;
          };
        };

      applyTheme = pkgs.writeShellApplication {
        name = "apply-theme";
        runtimeInputs =
          with pkgs;
          [
            coreutils
            gnused
          ]
          # macOS provides pkill and pgrep.
          ++ lib.optionals stdenv.hostPlatform.isLinux [
            procps
            niri
            systemd
          ];
        text = ''
          mode=''${1:?expected light or dark}
          current=$(cat "${themeDir}/mode" 2>/dev/null || true)
          if [ "$current" != "$mode" ]; then
            base=$(readlink -f "${baseLink}")
            case "$mode" in
              # THEME_SWITCH stops themeBase from reapplying the mode a second time.
              dark) THEME_SWITCH=1 "$base/activate" ;;
              light) THEME_SWITCH=1 "$base/specialisation/light/activate" ;;
              *) echo "apply-theme: unsupported mode: $mode" >&2; exit 2 ;;
            esac
          fi

          # foot holds both palettes; the signal selects one.
          if [ "$mode" = dark ]; then pkill -USR1 -x foot || true; else pkill -USR2 -x foot || true; fi
          # nvim, waybar and qutebrowser run as Nix wrappers named .<name>-wrapped.
          # pkill matches at most 15 characters of the name without -f.
          pkill -USR1 -x nvim || true
          pkill -USR1 -x '\.nvim-wrapped' || true
          systemctl --user kill --kill-whom=main --signal=USR2 waybar.service 2>/dev/null || true
          if systemctl --user is-active --quiet swaync.service 2>/dev/null; then
            swaync-client --reload-css >/dev/null 2>&1 || true
          fi
          if systemctl --user is-active --quiet noctalia.service 2>/dev/null && command -v noctalia >/dev/null; then
            noctalia msg config-reload >/dev/null 2>&1 || true
          fi
          systemctl --user try-restart swayosd.service 2>/dev/null || true
          # darkman starts before the compositor, so its environment has no
          # NIRI_SOCKET or UMBRIEL_SOCKET.
          if [ -z "''${NIRI_SOCKET:-}" ] && command -v systemctl >/dev/null; then
            NIRI_SOCKET=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^NIRI_SOCKET=//p' || true)
            export NIRI_SOCKET
          fi
          if [ -n "''${NIRI_SOCKET:-}" ]; then niri msg action load-config-file >/dev/null 2>&1 || true; fi
          if [ -z "''${UMBRIEL_SOCKET:-}" ] && command -v systemctl >/dev/null; then
            UMBRIEL_SOCKET=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^UMBRIEL_SOCKET=//p' || true)
            export UMBRIEL_SOCKET
          fi
          if [ -n "''${UMBRIEL_SOCKET:-}" ] && command -v umbriel >/dev/null; then
            umbriel msg config-reload >/dev/null 2>&1 || true
          fi
          if pgrep -f '(/bin/\.?qutebrowser(-wrapped)?|/MacOS/qutebrowser)( |$)' >/dev/null; then qutebrowser ':config-source' >/dev/null 2>&1 || true; fi
          if tmux list-sessions >/dev/null 2>&1; then tmux source-file "${themeDir}/tmux.conf" || true; fi
          for session in $(kak -l 2>/dev/null || true); do
            printf 'source %s\n' "${themeDir}/theme.kak" | kak -p "$session" >/dev/null 2>&1 || true
          done
          rmpc_pid=$(pgrep -x rmpc | head -1 || true)
          if [ -n "$rmpc_pid" ]; then
            rmpc remote --pid "$rmpc_pid" set theme "${themeDir}/rmpc.ron" >/dev/null 2>&1 || true
          fi

          # btop reloads its config and theme on SIGUSR2.
          pkill -USR2 -x btop || true
        '';
      };
    in
    {
      imports = [ inputs.stylix.homeModules.stylix ];

      options.theme.mode = lib.mkOption {
        type = lib.types.enum [
          "dark"
          "light"
        ];
        default = "dark";
        description = "Palette this generation is built with.";
      };

      config = {
        specialisation.light.configuration.theme.mode = "light";

        fonts.fontconfig.enable = true;

        stylix = {
          enable = true;
          autoEnable = false;
          base16Scheme = monobiome.base16 mode p;
          polarity = mode;
          fonts = {
            monospace = {
              name = "Berkeley Mono";
              package = pkgs.runCommand "berkeley-mono" { } ''
                install -Dm644 ${inputs.berkeley-mono}/fonts/*.ttf -t $out/share/fonts/truetype
              '';
            };
            sansSerif = {
              name = "Noto Sans";
              package = pkgs.noto-fonts;
            };
            serif = {
              name = "Noto Serif";
              package = pkgs.noto-fonts;
            };
            emoji = {
              name = "Noto Color Emoji";
              package = pkgs.noto-fonts-color-emoji;
            };
          };
          cursor = lib.mkIf isLinux {
            name = "Adwaita";
            package = adwaitaIcons;
            size = 24;
          };
          targets = {
            gtk.enable = isLinux;
            qt.enable = isLinux;
            fontconfig.enable = true;
            font-packages.enable = true;
          };
        };

        services.darkman = lib.mkIf isLinux {
          enable = true;
          settings = {
            lat = 36;
            lng = -79;
            usegeoclue = false;
            portal = true;
          };
          scripts.theme = ''${lib.getExe applyTheme} "$1"'';
        };

        # Recorded by every normal switch (not by the light specialisation),
        # because activating a specialisation creates a generation without
        # specialisations of its own. The current mode is then reapplied
        # asynchronously: theme-sync on Linux, the appearance agent on macOS.
        home.activation.themeBase = lib.mkIf (config.specialisation != { }) (
          lib.hm.dag.entryAfter [ "linkGeneration" "setupLaunchAgents" ] (
            ''
              run mkdir -p "$(dirname "${baseLink}")"
              run ln -sfn "$newGenPath" "${baseLink}"
            ''
            + (
              if isLinux then
                ''
                  if [ -z "''${THEME_SWITCH:-}" ] && ${pkgs.systemd}/bin/systemctl --user is-active --quiet darkman.service; then
                    run ${pkgs.systemd}/bin/systemctl --user start --no-block theme-sync.service
                  fi
                ''
              else
                ''
                  if [ -z "''${THEME_SWITCH:-}" ]; then
                    run /bin/launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.theme-appearance" || true
                  fi
                ''
            )
          )
        );
        systemd.user.services.theme-sync = lib.mkIf isLinux {
          Unit.Description = "Apply darkman's current mode";
          Service = {
            Type = "oneshot";
            ExecStart = toString (
              pkgs.writeShellScript "theme-sync" ''
                ${lib.getExe applyTheme} "$(${lib.getExe pkgs.darkman} get)"
              ''
            );
          };
        };

        xdg.configFile = {
          "theme/mode".text = "${mode}\n";

          "theme/tmux.conf".text = ''
            set -g @theme-bg '#${p.bg}'
            set -g @theme-bg-alt '#${p.bg_alt}'
            set -g @theme-selection '#${p.selection}'
            set -g @theme-border '#${p.border}'
            set -g @theme-muted '#${p.muted}'
            set -g @theme-fg '#${p.fg_max}'
            set -g @theme-blue '#${p.blue}'
            set -g @theme-red '#${p.red}'
          '';

          "theme/fzf.fish".text = ''
            set -gx FZF_DEFAULT_OPTS     '--color=fg:#${p.fg_max},bg:#${p.bg},hl:#${p.red}'     '--color=fg+:#${p.fg_max},bg+:#${p.selection},hl+:#${p.red_bright}'     '--color=info:#${p.yellow},prompt:#${p.green},pointer:#${p.blue}'     '--color=marker:#${p.green},spinner:#${p.yellow},header:#${p.blue}'
          '';

          "theme/delta.gitconfig".text = ''
            [delta]
                dark = ${lib.boolToString (mode == "dark")}
                light = ${lib.boolToString (mode == "light")}
                syntax-theme = none
                file-style = bold "#${p.blue}"
                file-decoration-style = "#${p.border}" ul
                hunk-header-style = file line-number syntax
                hunk-header-file-style = "#${p.fg}"
                hunk-header-line-number-style = "#${p.orange}"
                hunk-header-decoration-style = "#${p.border}" box
                commit-style = raw
                commit-decoration-style = "#${p.border}" box
                zero-style = "#${p.fg_max}"
                plus-style = "#${p.green}"
                plus-emph-style = "#${p.green_bright}" bold
                minus-style = "#${p.red}"
                minus-emph-style = "#${p.red_bright}" bold
                line-numbers = true
                line-numbers-zero-style = "#${p.muted}"
                line-numbers-minus-style = "#${p.red}"
                line-numbers-plus-style = "#${p.green}"
                whitespace-error-style = "#${p.bg}" "#${p.red}"
                blame-palette = "#${p.bg} #${p.bg_alt} #${p.selection} #${p.border}"
          '';

          "theme/mpv.conf".text = ''
            osd-font='${monospace}'
            osd-color='#${p.fg_max}'
            osd-border-color='#${p.bg}'
            osd-shadow-color='#${p.bg}'
          '';

          "theme/qutebrowser.conf".text = ''
            mode=${mode}
            font=${monospace}
            bg=#${p.bg}
            bg_alt=#${p.bg_alt}
            bg_soft=#${p.selection}
            selection=#${p.selection}
            border=#${p.border}
            muted=#${p.muted}
            fg=#${p.fg_max}
            fg_alt=#${p.fg_bright}
            blue=#${p.blue}
            green=#${p.green}
            green_alt=#${p.green_bright}
            magenta=#${p.orange}
            yellow=#${p.yellow}
            yellow_bright=#${p.yellow_bright}
            red=#${p.red}
            rust=#${p.orange}
          '';

          "theme/zathurarc".text = ''
            set default-bg "#${p.bg}"
            set default-fg "#${p.fg_max}"
            set statusbar-bg "#${p.bg_alt}"
            set statusbar-fg "#${p.fg_max}"
            set inputbar-bg "#${p.bg_alt}"
            set inputbar-fg "#${p.fg_max}"
            set completion-bg "#${p.bg}"
            set completion-fg "#${p.fg_max}"
            set completion-group-bg "#${p.bg_alt}"
            set completion-group-fg "#${p.muted}"
            set completion-highlight-bg "#${p.selection}"
            set completion-highlight-fg "#${p.fg_max}"
            set notification-bg "#${p.bg_alt}"
            set notification-fg "#${p.fg_max}"
            set notification-error-bg "#${p.bg_alt}"
            set notification-error-fg "#${p.red}"
            set notification-warning-bg "#${p.bg_alt}"
            set notification-warning-fg "#${p.yellow}"
            set index-bg "#${p.bg}"
            set index-fg "#${p.fg_max}"
            set index-active-bg "#${p.selection}"
            set index-active-fg "#${p.fg_max}"
            set highlight-color "#${p.selection}"
            set highlight-active-color "#${p.yellow}"
            set highlight-fg "#${p.fg_max}"
            set render-loading-bg "#${p.bg}"
            set render-loading-fg "#${p.fg_max}"
            set signature-error-color "#${p.red}"
            set signature-warning-color "#${p.yellow}"
            set signature-success-color "#${p.green}"
            set recolor ${lib.boolToString (mode == "dark")}
            set recolor-darkcolor "#${p.fg_max}"
            set recolor-lightcolor "#${p.bg}"
            set recolor-keephue true
            set recolor-adjust-lightness true
            set recolor-reverse-video true
          '';

          # btop only loads themes from its themes directories, by name.
          "btop/themes/monobiome.theme".text = ''
            theme[main_bg]="#${p.bg}"
            theme[main_fg]="#${p.fg_max}"
            theme[title]="#${p.blue}"
            theme[hi_fg]="#${p.red_bright}"
            theme[selected_bg]="#${p.selection}"
            theme[selected_fg]="#${p.fg_max}"
            theme[inactive_fg]="#${p.muted}"
            theme[graph_text]="#${p.fg_dim}"
            theme[meter_bg]="#${p.selection}"
            theme[followed_bg]="#${p.selection}"
            theme[followed_fg]="#${p.fg_max}"
            theme[proc_misc]="#${p.blue_bright}"
            theme[cpu_box]="#${p.border}"
            theme[mem_box]="#${p.border}"
            theme[net_box]="#${p.border}"
            theme[proc_box]="#${p.border}"
            theme[div_line]="#${p.border}"
            theme[temp_start]="#${p.green}"
            theme[temp_mid]="#${p.yellow}"
            theme[temp_end]="#${p.red}"
            theme[cpu_start]="#${p.green}"
            theme[cpu_mid]="#${p.yellow}"
            theme[cpu_end]="#${p.red}"
            theme[free_start]="#${p.green}"
            theme[free_mid]="#${p.blue}"
            theme[free_end]="#${p.blue_bright}"
            theme[cached_start]="#${p.fg_dim}"
            theme[cached_mid]="#${p.orange}"
            theme[cached_end]="#${p.orange_bright}"
            theme[available_start]="#${p.green}"
            theme[available_mid]="#${p.blue}"
            theme[available_end]="#${p.blue_bright}"
            theme[used_start]="#${p.green}"
            theme[used_mid]="#${p.yellow}"
            theme[used_end]="#${p.red}"
            theme[download_start]="#${p.green}"
            theme[download_mid]="#${p.blue}"
            theme[download_end]="#${p.blue_bright}"
            theme[upload_start]="#${p.orange}"
            theme[upload_mid]="#${p.red}"
            theme[upload_end]="#${p.red_bright}"
            theme[process_start]="#${p.green}"
            theme[process_mid]="#${p.yellow}"
            theme[process_end]="#${p.red}"
          '';

          "theme/rmpc.ron".text = ''
            #![enable(implicit_some)]
            #![enable(unwrap_newtypes)]
            #![enable(unwrap_variant_newtypes)]
            (
                background_color: "#${p.bg}",
                header_background_color: "#${p.bg}",
                modal_background_color: "#${p.bg_alt}",
                text_color: "#${p.fg_max}",
                preview_label_style: (fg: "#${p.yellow}"),
                preview_metadata_group_style: (fg: "#${p.yellow}", modifiers: "Bold"),
                highlighted_item_style: (fg: "#${p.bg}", bg: "#${p.blue}", modifiers: "Bold"),
                current_item_style: (fg: "#${p.bg}", bg: "#${p.yellow}", modifiers: "Bold"),
                borders_style: (fg: "#${p.border}"),
                highlight_border_style: (fg: "#${p.blue}"),
                tab_bar: (
                    active_style: (fg: "#${p.bg}", bg: "#${p.blue}", modifiers: "Bold"),
                    inactive_style: (fg: "#${p.muted}"),
                ),
                progress_bar: (
                    elapsed_style: (fg: "#${p.green}"),
                    thumb_style: (fg: "#${p.blue_bright}"),
                ),
            )
          '';

          "theme/theme.kak".text = ''
            set-face global value          rgb:${p.orange}
            set-face global type           rgb:${p.yellow}
            set-face global variable       rgb:${p.fg_max}
            set-face global module         rgb:${p.blue_bright}
            set-face global function       rgb:${p.blue}
            set-face global string         rgb:${p.green}
            set-face global keyword        rgb:${p.red}+b
            set-face global operator       rgb:${p.fg}
            set-face global attribute      rgb:${p.yellow_bright}
            set-face global comment        rgb:${p.muted}+i
            set-face global documentation  comment
            set-face global meta           rgb:${p.orange}
            set-face global builtin        rgb:${p.blue_bright}
            set-face global identifier     rgb:${p.fg_max}
            set-face global bracket        rgb:${p.fg}
            set-face global delimiter      rgb:${p.fg}
            set-face global title          rgb:${p.blue}+b
            set-face global header         rgb:${p.blue_bright}+b
            set-face global mono           rgb:${p.green_bright}
            set-face global block          rgb:${p.green_bright}
            set-face global link           rgb:${p.blue}+u
            set-face global bullet         rgb:${p.yellow}
            set-face global list           rgb:${p.fg_max}
            set-face global Default            rgb:${p.fg_max},rgb:${p.bg}
            set-face global CursorLine         default,rgb:${p.bg_alt}
            set-face global PrimarySelection   default,rgb:${p.selection}+g
            set-face global SecondarySelection default,rgb:${p.bg_alt}+g
            set-face global PrimaryCursor      rgb:${p.bg},rgb:${p.fg_max}+fg
            set-face global SecondaryCursor    rgb:${p.bg},rgb:${p.muted}+fg
            set-face global PrimaryCursorEol   rgb:${p.bg},rgb:${p.fg}+fg
            set-face global SecondaryCursorEol rgb:${p.bg},rgb:${p.border}+fg
            set-face global LineNumbers        rgb:${p.muted},rgb:${p.bg}
            set-face global LineNumberCursor   rgb:${p.yellow},rgb:${p.bg_alt}+b
            set-face global LineNumbersWrapped rgb:${p.border},rgb:${p.bg}
            set-face global MenuForeground     rgb:${p.bg},rgb:${p.blue}
            set-face global MenuBackground     rgb:${p.fg_max},rgb:${p.bg_alt}
            set-face global MenuInfo           rgb:${p.muted}+i
            set-face global Information        rgb:${p.fg_max},rgb:${p.bg_alt}
            set-face global InlineInformation  rgb:${p.fg_max},rgb:${p.bg_alt}
            set-face global Error              rgb:${p.bg},rgb:${p.red}
            set-face global StatusLine         rgb:${p.fg_max},rgb:${p.bg_alt}
            set-face global StatusLineMode     rgb:${p.bg},rgb:${p.yellow}+b
            set-face global StatusLineInfo     rgb:${p.blue_bright}
            set-face global StatusLineValue    rgb:${p.orange}
            set-face global StatusCursor       rgb:${p.bg},rgb:${p.fg_max}
            set-face global Prompt             rgb:${p.yellow},rgb:${p.bg_alt}
            set-face global MatchingChar       rgb:${p.yellow_bright},rgb:${p.selection}+b
            set-face global BufferPadding      rgb:${p.border},rgb:${p.bg}
            set-face global Whitespace         rgb:${p.border}+f
            set-face global WhitespaceIndent   rgb:${p.bg_alt}+f
            set-face global WrapMarker         rgb:${p.border}+f
            set-face global DiagnosticError        default,default,rgb:${p.red}+c
            set-face global DiagnosticWarning      default,default,rgb:${p.yellow}+c
            set-face global DiagnosticInfo         default,default,rgb:${p.blue}+c
            set-face global DiagnosticHint         default,default,rgb:${p.muted}+c
            set-face global InlayDiagnosticError   rgb:${p.red}+d
            set-face global InlayDiagnosticWarning rgb:${p.yellow}+d
            set-face global InlayDiagnosticInfo    rgb:${p.blue}+d
            set-face global InlayDiagnosticHint    rgb:${p.muted}+d
            set-face global LineFlagError          rgb:${p.red}
            set-face global LineFlagWarning        rgb:${p.yellow}
            set-face global LineFlagInfo           rgb:${p.blue}
            set-face global LineFlagHint           rgb:${p.muted}
            set-face global InlayHint              rgb:${p.muted}+d
            set-face global InlayCodeLens          rgb:${p.muted}+d
            set-face global Reference              default,rgb:${p.selection}
          '';
        }
        // lib.optionalAttrs isLinux {
          "theme/palette.css".text = ''
            @define-color background #${p.bg};
            @define-color background_alt #${p.bg_alt};
            @define-color background_soft #${p.selection};
            @define-color surface #${p.border};
            @define-color selection #${p.selection};
            @define-color border #${p.border};
            @define-color muted #${p.muted};
            @define-color foreground #${p.fg};
            @define-color foreground_bright #${p.fg_max};
            @define-color primary #${p.blue};
            @define-color accent #${p.orange};
            @define-color success #${p.green};
            @define-color warning #${p.yellow};
            @define-color error #${p.red};
          '';

          "theme/fonts.css".text = ''
            * { font-family: "${monospace}", "Symbols Nerd Font Mono", "Noto Sans", monospace; }
          '';

          "theme/foot.ini".text = ''
            [main]
            initial-color-theme=${mode}
            font=${monospace}:size=13:fontfeatures=-calt:-liga:-dlig, Symbols Nerd Font Mono:size=13
          ''
          + footColors "dark" monobiome.dark
          + footColors "light" monobiome.light;

          "theme/fuzzel.ini".text = ''
            [main]
            font=${monospace}:size=14, Symbols Nerd Font:size=14

            [colors]
            background=${p.bg}fa
            text=${p.fg_max}ff
            prompt=${p.yellow}ff
            placeholder=${p.muted}ff
            border=${p.blue}ff
            selection=${p.selection}ff
            selection-text=${p.fg_max}ff
            match=${p.red}ff
            selection-match=${p.orange}ff
          '';

          "theme/niri.kdl".text = ''
            layout {
                background-color "#${p.bg}"
                border {
                    active-color "#${p.blue}"
                    inactive-color "#${p.border}"
                    urgent-color "#${p.red}"
                }
                tab-indicator {
                    active-color "#${p.blue}"
                    inactive-color "#${p.border}"
                    urgent-color "#${p.red}"
                }
            }
            overview { backdrop-color "#${p.bg_alt}"; }
            window-rule {
                match is-window-cast-target=true
                focus-ring { on; width 3; active-color "#${p.red}"; inactive-color "#${p.red}"; }
            }
          '';

          "noctalia/palettes/monobiome.json".text = builtins.toJSON {
            dark = noctaliaPalette monobiome.dark;
            light = noctaliaPalette monobiome.light;
          };

          "theme/umbriel.toml".text = ''
            [colors]
            background = "#${p.bg}"
            backdrop = "#${p.bg}"
            accent_primary = "#${p.blue}"
            error = "#${p.red}"

            [colors.border]
            focused = "#${p.blue}"
            unfocused = "#${p.border}"
          '';

          "swaylock/config".text = ''
            color=${p.bg}
            image=${./lockscreen-${mode}.png}
            scaling=fill
            font=${monospace}
            font-size=24
            indicator-radius=72
            indicator-thickness=8
            indicator-caps-lock
            show-failed-attempts
            inside-color=${p.bg}f2
            inside-clear-color=${p.bg_alt}f2
            inside-caps-lock-color=${p.bg_alt}f2
            inside-ver-color=${p.bg_alt}f2
            inside-wrong-color=${p.bg_alt}f2
            ring-color=${p.blue}
            ring-clear-color=${p.green}
            ring-caps-lock-color=${p.yellow}
            ring-ver-color=${p.blue_bright}
            ring-wrong-color=${p.red}
            key-hl-color=${p.orange}
            bs-hl-color=${p.red}
            separator-color=00000000
            line-color=00000000
            text-color=${p.fg_max}
            text-clear-color=${p.fg_max}
            text-caps-lock-color=${p.yellow}
            text-ver-color=${p.blue_bright}
            text-wrong-color=${p.red}
            layout-bg-color=${p.bg_alt}f2
            layout-border-color=${p.border}
            layout-text-color=${p.fg_max}
          '';
        };

        # macOS: dark-mode-notify runs the script at start and on every
        # appearance change, with DARKMODE=1 or 0.
        launchd.agents.theme-appearance = lib.mkIf (!isLinux) {
          enable = true;
          config = {
            ProgramArguments = [
              (lib.getExe pkgs.dark-mode-notify)
              (toString (
                pkgs.writeShellScript "theme-appearance" ''
                  if [ "''${DARKMODE:-0}" = 1 ]; then mode=dark; else mode=light; fi
                  exec ${lib.getExe applyTheme} "$mode"
                ''
              ))
            ];
            EnvironmentVariables.PATH = "${config.home.profileDirectory}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
            KeepAlive = true;
            RunAtLoad = true;
            ProcessType = "Interactive";
          };
        };

        home.packages = [ applyTheme ] ++ lib.optional isLinux pkgs.adwaita-icon-theme-legacy;
      };
    };
}
