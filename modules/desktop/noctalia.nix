{ config, inputs, ... }:
let
  inherit (config.flake.lib) outsideUmbriel;
  inherit (config.meta) user;
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
      systemd.user.services.nm-applet.unitConfig = outsideUmbriel;

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
    in
    {
      imports = [ inputs.noctalia.homeModules.default ];

      programs.noctalia = {
        enable = true;
        systemd.enable = true;
        settings = {
          shell = {
            font_family = config.stylix.fonts.monospace.name;
            corner_radius_scale = 0.0;
            polkit_agent = true;
            launch_apps_as_systemd_services = true;
            telemetry_enabled = false;
            setup_wizard_enabled = false;
            greeter_sync.auto_sync = true;
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
          };

          wallpaper.enabled = false;
          backdrop.enabled = false;
          dock.enabled = false;
          desktop_widgets.enabled = false;

          osd.position = "bottom_center";

          lockscreen = {
            enabled = true;
            allow_empty_password = true;
            wallpaper = "${../theme/lockscreen-${mode}.png}";
            blur_intensity = 0.0;
            tint_intensity = 0.0;
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
              start = [ "workspaces" ];
              center = [ "active_window" ];
              end = [
                "cpu"
                "ram"
                "media"
                "network"
                "bluetooth"
                "volume"
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
              max_length = 400;
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
