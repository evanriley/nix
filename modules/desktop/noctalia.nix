{ config, inputs, ... }:
let
  inherit (config.meta) user repoDir location;
in
{
  flake.modules.nixos.noctalia =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.noctalia-greeter.nixosModules.default ];

      security.pam.services.login = {
        u2fAuth = true;
        rules.auth.u2f.order = 13500;
      };

      age.secrets.fastmail-caldav = {
        file = inputs.self + "/secrets/${config.networking.hostName}/fastmail-caldav.age";
        owner = user.name;
        mode = "0400";
      };

      services.displayManager.noctalia-greeter = {
        enable = true;
        passwordless-sync-users = [ user.name ];
        cursorTheme.package = pkgs.adwaita-icon-theme;
        settings = {
          session.default = "Umbriel";
          user.default = user.name;
          appearance = {
            scheme = "Synced";
            hide_logo = true;
            scheme_selector_position = "hidden";
          };
          cursor = {
            theme = "Adwaita";
            size = 24;
          };
          keyboard.numlock = true;
          auth.allow_empty_password = false;
        };
      };

      systemd.services.plymouth-quit.serviceConfig.ExecStart = [
        ""
        "-${config.boot.plymouth.package}/bin/plymouth quit --retain-splash"
      ];
      systemd.services.greetd.serviceConfig.Type = lib.mkForce "simple";

      systemd.services.noctalia-drive-health = {
        description = "Collect read-only SMART data for Noctalia Drive Health";
        after = [ "local-fs.target" ];
        path = with pkgs; [
          coreutils
          gnused
          smartmontools
          util-linux
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.bash}/bin/sh ${inputs.noctalia-plugins-community}/drive-health/scripts/collect_raw.sh --output /run/noctalia-drive-health/raw.json";
          Group = config.users.users.${user.name}.group;
          RuntimeDirectory = "noctalia-drive-health";
          RuntimeDirectoryMode = "0750";
          RuntimeDirectoryPreserve = true;
          UMask = "0027";
          StandardOutput = "null";
          TimeoutStartSec = "60s";
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateNetwork = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          RestrictAddressFamilies = "AF_UNIX";
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          CapabilityBoundingSet = "CAP_DAC_OVERRIDE CAP_SYS_ADMIN CAP_SYS_RAWIO";
          ReadWritePaths = "/run/noctalia-drive-health";
        };
      };
      systemd.timers.noctalia-drive-health = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "20s";
          OnUnitActiveSec = "15min";
          AccuracySec = "5s";
        };
      };
    };

  flake.modules.homeManager.noctalia =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.theme) mode;
      stateDir = "${config.xdg.stateHome}/noctalia";
      wallpaperDir = "${config.home.homeDirectory}/Pictures/wallpapers";
      wallpapers = {
        dark = "dark-snake.jpg";
        light = "light-building.jpg";
      };

      official = inputs.noctalia-plugins-official;
      community = inputs.noctalia-plugins-community;
      plugins = {
        "noctalia/umbriel-companion" = "${official}/umbriel-companion";
        "noctalia/screen_recorder" = "${official}/screen_recorder";
        "mindnbytes/nix-status" = "${community}/nix-status";
        "srounce/systemd" = "${community}/systemd";
        "knyrps/nix-search" = "${community}/nix-search";
        "rylos/syncthing" = "${community}/syncthing";
        "rylos/tailnet" = "${community}/tailnet";
        "blackbartblues/audio-switcher" = "${community}/audio-switcher";
        "dunarand/tmux-provider" = "${community}/tmux-provider";
        "cleboost/ssh-launcher" = "${community}/ssh-launcher";
        "raycursive/github-prs" = "${community}/github-prs";
        "hy4ri/github-notifications" = "${community}/github-notifications";
        "jrohland/claudecode" = "${community}/claudecode";
        "alexander/game-launcher" = "${community}/game-launcher";
        "alexander/screen-toolkit" = "${community}/screen-toolkit";
        "gustav0ar/drive-health" = "${community}/drive-health";
        "dotnetrob/cat" = "${community}/cat";
      };

      pluginDir = pkgs.runCommandCC "noctalia-plugins" { } ''
        mkdir $out
        ${lib.concatMapStrings (path: "cp -r ${path} $out/\n") (lib.attrValues plugins)}
        chmod -R u+w $out/game-launcher
        cd $out/game-launcher
        $CC -O2 -o gamelauncher gamelauncher.c sqlite_reader.c
        for panel in panel.luau original.luau; do
          substituteInPlace $panel \
            --replace-fail "if not buildTagFile then return true end" "do return true end"
        done
      '';

      pluginTools = with pkgs; [
        bc
        curl
        fzf
        gh
        glib
        grim
        hyprpicker
        imagemagick
        jq
        nix-search-tv
        pulseaudio
        slurp
        smartmontools
        (tesseract.override { enableLanguages = [ "eng" ]; })
        util-linux
        xdg-utils
        zbar
        ffmpeg
      ];

      pluginWidget = type: settings: { inherit type; } // settings;
    in
    {
      imports = [ inputs.noctalia.homeModules.default ];

      programs.noctalia = {
        enable = true;
        systemd.enable = true;
        package =
          let
            upstream = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
          in
          pkgs.symlinkJoin {
            name = "noctalia-${upstream.version}";
            paths = [ upstream ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/noctalia --suffix PATH : ${lib.makeBinPath pluginTools}
            '';
            meta.mainProgram = "noctalia";
          };
        settings = {
          shell = {
            font_family = config.stylix.fonts.monospace.name;
            corner_radius_scale = 0.0;
            polkit_agent = true;
            launch_apps_as_systemd_services = true;
            telemetry_enabled = false;
            setup_wizard_enabled = false;
            greeter_sync.auto_sync = true;
            umbriel_overview_type_to_launch_enabled = true;
            window_switcher = {
              style = "compact";
              mru = true;
            };
            panel = {
              shadow = false;
              transparency_mode = "solid";
            };
            screenshot = {
              directory = "~/Pictures/Screenshots";
              filename_pattern = "%Y-%m-%d_%H-%M-%S";
              save_to_file = true;
              copy_to_clipboard = true;
            };
          };

          theme = {
            inherit mode;
            source = "custom";
            custom_palette = "monobiome";
            templates = {
              enable_builtin_templates = false;
              enable_community_templates = false;
            };
          };

          wallpaper = {
            enabled = true;
            directory = wallpaperDir;
            fill_color = "surface";
            transition = [ "fade" ];
            default.path = "${wallpaperDir}/${wallpapers.${mode}}";
          };
          backdrop.enabled = false;
          dock.enabled = false;
          desktop_widgets.enabled = false;

          osd.position = "bottom_center";

          audio.enable_sounds = false;

          nightlight.enabled = true;

          notification = {
            filter_order = [ "syncthing_devices" ];
            filter.syncthing_devices = {
              enabled = true;
              match = "noctalia";
              match_content = "^.+ (dis)?connected\\.$";
              show_toast = false;
              play_sound = false;
            };
          };

          calendar = {
            enabled = true;
            account.fastmail = {
              type = "caldav";
              name = "Fastmail";
              provider = "custom";
              server_url = "https://caldav.fastmail.com/dav/";
              username = user.email;
              calendars = [ ];
              credential_source = "file";
              password_file = "/run/agenix/fastmail-caldav";
            };
          };

          location = {
            auto_locate = false;
            address = "";
            inherit (location) latitude longitude;
          };
          weather = {
            enabled = true;
            unit = "imperial";
          };

          lockscreen = {
            enabled = true;
            allow_empty_password = true;
            blur_intensity = 0.0;
            tint_intensity = 0.3;
          };

          idle.behavior = {
            lock = {
              enabled = true;
              timeout = 300;
              action = "lock";
            };
            screen-off = {
              enabled = true;
              timeout = 600;
              action = "screen_off";
            };
            suspend = {
              enabled = true;
              timeout = 1800;
              action = "lock_and_suspend";
            };
          };

          bar = {
            order = [ "main" ];
            main = {
              position = "bottom";
              layer = "overlay";
              auto_hide = true;
              show_on_workspace_switch = false;
              reserve_space = false;
              thickness = 30;
              radius = 0;
              concave_edge_corners = false;
              margin_ends = 0;
              margin_edge = 0;
              shadow = false;
              capsule = false;
              widget_spacing = 12;
              start = [
                "workspaces"
                "umbriel_layout"
              ];
              center = [ "active_window" ];
              end = [
                "cat"
                "cpu"
                "ram"
                "drive_health"
                "media"
                "claude"
                "github_prs"
                "github_notifications"
                "nix_status"
                "syncthing"
                "tailnet"
                "network"
                "bluetooth"
                "audio"
                "recorder"
                "caffeine"
                "tray"
                "clock"
                "notifications"
                "control-center"
                "session"
              ];
            };
          };

          widget = {
            workspaces = {
              style = "minimal";
              label_source = "name";
              max_label_chars = 10;
            };
            active_window = {
              type = "active_window";
              display = "text_only";
              max_length = 280;
            };
            cpu = {
              type = "sysmon";
              stat = "cpu_usage";
              visualization = "none";
            };
            ram = {
              type = "sysmon";
              stat = "ram_used";
              visualization = "none";
            };
            clock = {
              format = "{:%a %H:%M}";
              tooltip_format = "{:%Y-%m-%d}";
            };
            media.title_scroll = "always";
            umbriel_layout = pluginWidget "noctalia/umbriel-companion:bar" { };
            cat = pluginWidget "dotnetrob/cat:cat" { };
            drive_health = pluginWidget "gustav0ar/drive-health:summary" { };
            claude = pluginWidget "jrohland/claudecode:pill" { };
            github_prs = pluginWidget "raycursive/github-prs:bar" { };
            github_notifications = pluginWidget "hy4ri/github-notifications:inbox" { };
            nix_status = pluginWidget "mindnbytes/nix-status:status" { };
            syncthing = pluginWidget "rylos/syncthing:bar" { };
            tailnet = pluginWidget "rylos/tailnet:bar" { };
            audio = pluginWidget "blackbartblues/audio-switcher:widget" { };
            recorder = pluginWidget "noctalia/screen_recorder:recorder" { };
          };

          plugins = {
            auto_update = "none";
            enabled = lib.attrNames plugins;
            source = [
              {
                name = "official";
                kind = "git";
                location = "https://github.com/noctalia-dev/official-plugins";
                enabled = false;
              }
              {
                name = "community";
                kind = "git";
                location = "https://github.com/noctalia-dev/community-plugins";
                enabled = false;
              }
              {
                name = "nix";
                kind = "path";
                location = "${pluginDir}";
                enabled = true;
              }
            ];
          };

          plugin_settings = {
            "mindnbytes/nix-status".flake_dir = "${config.home.homeDirectory}/${repoDir}";
            "noctalia/screen_recorder" = {
              video_source = "focused";
              video_codec = "av1";
              directory = "${config.home.homeDirectory}/Videos/Recordings";
              replay_enabled = false;
            };
            "gustav0ar/drive-health".system_collector_enabled = true;
            "raycursive/github-prs".rules = [
              "author:@me"
              "review-requested:@me"
            ];
          };
        };
      };

      systemd.user.services.noctalia = {
        Unit = {
          ConditionEnvironment = "XDG_CURRENT_DESKTOP=umbriel";
          X-Restart-Triggers = lib.mkForce [ ];
        };
        Service.ExecStartPre = "${pkgs.coreutils}/bin/rm -f ${stateDir}/settings.toml";
      };
    };
}
