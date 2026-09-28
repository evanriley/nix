{ config, inputs, ... }:
let
  inherit (config.flake.lib) portalInterfaces xwaylandSatellite;

  # The package puts its own xwayland-satellite first on PATH.
  umbrielPackage =
    pkgs:
    inputs.umbriel.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
      xwayland-satellite = xwaylandSatellite pkgs;
    };
in
{
  flake.lib = { inherit umbrielPackage; };

  flake.modules.nixos.umbriel =
    { pkgs, ... }:
    {
      imports = [ inputs.umbriel.nixosModules.default ];

      programs.umbriel = {
        enable = true;
        package = umbrielPackage pkgs;
      };

      xdg.portal.config.umbriel = {
        default = [
          "umbriel"
          "gtk"
        ];
      }
      // portalInterfaces;
    };

  flake.modules.homeManager.umbriel =
    { config, lib, ... }:
    let
      bin = "${config.home.homeDirectory}/.local/bin";
      workspaces = [
        "web"
        "social"
        "game"
        "misc"
        "system"
        "extra"
      ];

      spawn = command: {
        action = "spawn:${command}";
        repeat = false;
      };
      noctalia = command: spawn "noctalia msg ${command}";
      noctaliaWhenLocked = command: {
        action = "spawn:noctalia msg ${command}";
        allow_when_locked = true;
      };
      withCooldown = action: {
        inherit action;
        cooldown_ms = 150;
      };

      # Mod+1-6 select named workspaces, Mod+7-9 positions.
      workspaceBinds = lib.listToAttrs (
        lib.concatLists (
          lib.imap1 (
            index: target:
            let
              key = toString index;
            in
            [
              (lib.nameValuePair "Mod+${key}" "workspace-switch:${target}")
              (lib.nameValuePair "Mod+Shift+${key}" "column-move-to-workspace:${target}")
            ]
          ) (workspaces ++ map toString (lib.range 7 9))
        )
      );

      rule = match: settings: { inherit match; } // settings;
      floating = width: height: {
        default_floating = true;
        default_floating_size_px = { inherit width height; };
      };
    in
    {
      imports = [ inputs.umbriel.homeModules.default ];

      programs.umbriel = {
        enable = true;
        # The system module installs it.
        package = null;
        settings = {
          include.optional.files = [ "${config.xdg.configHome}/theme/umbriel.toml" ];

          general.show_cheatsheet = false;

          input = {
            keyboard = {
              repeat_delay = 300;
              repeat_rate = 90;
              numlock_toggle = true;
            };
            touchpad = {
              tap = true;
              disable_while_typing = true;
            };
            mouse = {
              accel_profile = "flat";
              sensitivity = 0.0;
            };
            cursor = {
              size = 24;
              follows_focus = true;
            };
            focus = {
              follows_mouse = true;
              follows_mouse_max_scroll = 0.1;
            };
          };

          appearance = {
            border_width = 2;
            prefer_no_csd = true;
            corner_radius = 0;
            blur.enabled = false;
            shadow.enabled = false;
          };

          colors.overview.background_tint = "#00000000";
          overview.background_blur = false;

          # Springs settle faster with higher stiffness; umbriel's defaults
          # are 800-1400.
          animation = {
            duration_ms = 180;
            windows_in = {
              curve = "spring:1,1400";
              style = "popin";
              scale = 0.9;
            };
            windows_out = {
              curve = "spring:1,2200";
              style = "popin";
              scale = 0.9;
            };
            windows_move.curve = "spring:1,1400";
            workspaces.curve = "spring:1,1300";
            overview = {
              curve = "spring:1,1300";
              workspace_curve = "spring:1,1600";
            };
            scratchpad.curve = "spring:1,1300";
            border.curve = "spring:1,1400";
          };

          layout = {
            gap = 6;
            extent_presets = [
              0.25
              0.5
              1.0
            ];
            scrolling = {
              default_extent_fraction = 1.0;
              center_focused = "never";
            };
            master.default_width_fraction = 0.5;
          };

          workspaces.back_and_forth = true;
          workspace = map (
            name: { inherit name; } // lib.optionalAttrs (name == "web") { layout.mode = "master"; }
          ) workspaces;

          scratchpad = [
            { name = "btop"; }
            { name = "rmpc"; }
          ];

          # std::regex has no (?i); spell out case variants.
          window_rule = [
            (rule { is_scratchpad = true; } {
              corner_radius = 10;
              shadow = true;
            })
            (rule { app_id = "^foot$"; } { default_scrolling_extent = 0.5; })
            (rule {
              app_id = "^([Ff]irefox|org\\.mozilla\\.firefox|[Ll]ibre[Ww]olf|com\\.brave\\.Browser|brave-browser|org\\.qutebrowser\\.qutebrowser|qutebrowser)$";
            } { default_workspace = "web"; })
            (rule { app_id = "^([Dd]iscord|com\\.discordapp\\.Discord)$"; } {
              default_workspace = "social";
              default_focused = false;
            })
            (rule { app_id = "^dev\\.deedles\\.Trayscale$"; } (
              { default_workspace = "system"; } // floating 520 620
            ))
            (rule {
              app_id = "^[Ss]team$";
              title = "^(Steam|Friends List)$";
            } { default_workspace = "game"; })
            (rule { app_id = "^steam_app_[0-9]+$"; } { default_workspace = "game"; })
            # Unity's native Linux builds.
            (rule { app_id = "\\.x86_64$"; } { default_workspace = "game"; })
            (rule {
              app_id = "^steam_app_default$";
              title = "^[Bb]attle\\.net";
            } { default_workspace = "game"; })
            (rule { app_id = "([Ff]augus|[Bb]attle\\.net)"; } { default_workspace = "game"; })
            (rule { app_id = "(^(steam_app_[0-9]+|steam_app_default|gamescope)$|\\.x86_64$)"; } {
              vrr = "always";
              tearing = true;
            })
            (rule { title = "^Picture-in-Picture$"; } {
              default_floating = true;
              default_pinned = true;
            })
            (rule
              {
                app_id = "^[Ss]team$";
                title = "^notificationtoasts_[0-9]+_desktop$";
              }
              {
                default_floating = true;
                default_focused = false;
                default_position = {
                  x = 10;
                  y = 10;
                  anchor = "bottom_right";
                };
              }
            )
            (rule { app_id = "^(org\\.gnome\\.Nautilus|nautilus)$"; } (floating 1400 900))
            (rule { app_id = "^mpv$"; } (floating 1920 1080))
            (rule { app_id = "^swayimg$"; } (floating 1280 800))
            (rule { app_id = "^(org\\.pulseaudio\\.pavucontrol|pavucontrol)$"; } (floating 800 600))
            (rule { app_id = "^dev\\.noctalia\\.Noctalia$"; } (floating 1020 900))
            (rule {
              app_id = "^[Ss]team$";
              title = "^Friends List$";
            } (floating 600 700))
            (rule { app_id = "^scratch_btop$"; } ({ default_scratchpad = "btop"; } // floating 1920 1080))
            (rule { app_id = "^scratch_rmpc$"; } ({ default_scratchpad = "rmpc"; } // floating 1920 1080))
          ];

          keybinds = {
            "Mod+Return" = spawn "foot";
            "Mod+Space" = noctalia "panel-toggle launcher";
            "Mod+S" = noctalia "panel-toggle control-center";
            "Mod+G" = noctalia "panel-toggle alexander/game-launcher:browser";
            "Mod+Shift+S" = noctalia "panel-toggle alexander/screen-toolkit:panel";
            "Mod+E" = spawn "nautilus";
            "Mod+P" = noctalia "panel-toggle session";
            "Mod+Shift+E" = noctalia "panel-toggle session";
            "Ctrl+Alt+Delete" = noctalia "panel-toggle session";
            "Mod+Alt+L" = noctalia "session lock";
            "Mod+Ctrl+T" = spawn "${bin}/desktopctl scratch btop";
            "Mod+Ctrl+R" = spawn "${bin}/desktopctl scratch rmpc";
            "Mod+Ctrl+N" = noctalia "panel-toggle control-center notifications";
            "Mod+Ctrl+B" = noctalia "bar-toggle";
            "Mod+Alt+V" = noctalia "panel-toggle clipboard";
            "Mod+Alt+M" = spawn "${bin}/watch-media";
            "Print" = noctalia "screenshot-region";
            "Ctrl+Print" = noctalia "screenshot-fullscreen";
            "Alt+Print" = spawn "${bin}/desktopctl screenshot window";
            "Shift+Print" =
              spawn "systemctl --user kill --signal=SIGUSR1 --kill-whom=main gpu-screen-recorder-replay.service";

            "Mod+O" = "overview-toggle";
            "Mod+Q" = "window-close";
            "Mod+Shift+P" = "window-toggle-pinned";
            "Mod+Ctrl+Space" = "workspace-set-layout:toggle";
            "Alt+Tab" = "window-focus-last";
            "Mod+MouseMiddle" = "layout-scroll-drag";
            "Mod+Home" = "column-focus-first";
            "Mod+End" = "column-focus-last";
            "Mod+Ctrl+Home" = "column-move-to-first";
            "Mod+Ctrl+End" = "column-move-to-last";
            "Mod+BracketLeft" = "window-consume-or-expel-left";
            "Mod+BracketRight" = "window-consume-or-expel-right";
            "Mod+R" = "window-cycle-primary-extent";
            "Mod+Shift+R" = "window-cycle-secondary-extent";
            "Mod+F" = "window-toggle-maximize";
            "Mod+Shift+F" = "window-toggle-fullscreen";
            "Mod+C" = "column-center";
            "Mod+Minus" = "window-modify-primary-extent:-0.1";
            "Mod+Equal" = "window-modify-primary-extent:0.1";
            "Mod+Shift+Minus" = "window-modify-secondary-extent:-0.1";
            "Mod+Shift+Equal" = "window-modify-secondary-extent:0.1";
            "Mod+V" = "window-toggle-floating";
            "Mod+Shift+V" = "window-focus-switch-floating";
            "Mod+Shift+Slash" = "cheatsheet-toggle";

            "Mod+H" = "window-focus-left";
            "Mod+Shift+H" = "column-move-left";
            "Mod+Ctrl+H" = "output-focus-left";
            "Mod+Ctrl+Shift+H" = "column-move-to-output-left";
            "Mod+J" = "window-focus-down";
            "Mod+Shift+J" = "window-move-down";
            "Mod+Ctrl+J" = "output-focus-down";
            "Mod+Ctrl+Shift+J" = "column-move-to-output-down";
            "Mod+K" = "window-focus-up";
            "Mod+Shift+K" = "window-move-up";
            "Mod+Ctrl+K" = "output-focus-up";
            "Mod+Ctrl+Shift+K" = "column-move-to-output-up";
            "Mod+L" = "window-focus-right";
            "Mod+Shift+L" = "column-move-right";
            "Mod+Ctrl+L" = "output-focus-right";
            "Mod+Ctrl+Shift+L" = "column-move-to-output-right";

            "Mod+U" = "workspace-next";
            "Mod+Shift+U" = "column-move-to-workspace-next";
            "Mod+Ctrl+Shift+U" = "workspace-move-down";
            "Mod+I" = "workspace-previous";
            "Mod+Shift+I" = "column-move-to-workspace-previous";
            "Mod+Ctrl+Shift+I" = "workspace-move-up";
            "Mod+Page_Down" = "workspace-next";
            "Mod+Shift+Page_Down" = "column-move-to-workspace-next";
            "Mod+Ctrl+Shift+Page_Down" = "workspace-move-down";
            "Mod+Page_Up" = "workspace-previous";
            "Mod+Shift+Page_Up" = "column-move-to-workspace-previous";
            "Mod+Ctrl+Shift+Page_Up" = "workspace-move-up";

            "Mod+WheelDown" = withCooldown "workspace-next";
            "Mod+Ctrl+WheelDown" = withCooldown "column-move-to-workspace-next";
            "Mod+Shift+WheelDown" = "window-focus-right";
            "Mod+Ctrl+Shift+WheelDown" = "column-move-right";
            "Mod+WheelUp" = withCooldown "workspace-previous";
            "Mod+Ctrl+WheelUp" = withCooldown "column-move-to-workspace-previous";
            "Mod+Shift+WheelUp" = "window-focus-left";
            "Mod+Ctrl+Shift+WheelUp" = "column-move-left";
            "Mod+WheelLeft" = "window-focus-left";
            "Mod+Ctrl+WheelLeft" = "column-move-left";
            "Mod+WheelRight" = "window-focus-right";
            "Mod+Ctrl+WheelRight" = "column-move-right";

            "XF86AudioRaiseVolume" = noctaliaWhenLocked "volume-up";
            "XF86AudioLowerVolume" = noctaliaWhenLocked "volume-down";
            "XF86AudioMute" = noctaliaWhenLocked "volume-mute";
            "XF86AudioMicMute" = noctaliaWhenLocked "mic-mute";
            "XF86AudioPlay" = noctaliaWhenLocked "media toggle";
            "XF86AudioStop" = noctaliaWhenLocked "media stop";
            "XF86AudioPrev" = noctaliaWhenLocked "media previous";
            "XF86AudioNext" = noctaliaWhenLocked "media next";
          }
          // workspaceBinds;
        };
      };
    };
}
