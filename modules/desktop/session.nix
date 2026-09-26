let
  sessionService =
    {
      description,
      exec,
      service ? { },
      unit ? { },
    }:
    {
      Unit = {
        Description = description;
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
        Requisite = [ "graphical-session.target" ];
      }
      // unit;
      Service = {
        ExecStart = exec;
        Restart = "on-failure";
        RestartSec = 2;
      }
      // service;
      Install.WantedBy = [ "graphical-session.target" ];
    };
in
{ config, ... }:
let
  inherit (config.flake.lib) mkScript;
in
{
  flake.lib = { inherit sessionService; };

  flake.modules.homeManager.session =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      niri = "${pkgs.niri}/bin/niri";
      lock = "${pkgs.swaylock}/bin/swaylock -f";
      # display-mode pauses while this marker exists: the monitor drops its
      # mode list when powered off.
      monitorsOff = pkgs.writeShellScript "monitors-off" ''
        touch "$XDG_RUNTIME_DIR/monitors-off"
        exec ${niri} msg action power-off-monitors
      '';
      monitorsOn = pkgs.writeShellScript "monitors-on" ''
        ${niri} msg action power-on-monitors
        rm -f "$XDG_RUNTIME_DIR/monitors-off"
      '';
    in
    {
      dotfiles.config = [
        "foot"
        "fuzzel"
        "niri"
        "swaync/style.css"
        "swayosd/style.css"
        "waybar"
      ];
      home.file.".local/bin/desktopctl".source = lib.getExe (
        mkScript pkgs {
          name = "desktopctl";
          src = ./_scripts/desktopctl;
          runtimeInputs = [
            config.programs.btop.package
            config.programs.rmpc.package
          ]
          ++ (with pkgs; [
            niri
            foot
            fuzzel
            swaylock
            systemd
            procps
          ]);
        }
      );

      home.packages = with pkgs; [
        waybar
        swaynotificationcenter
        swayosd
        swaylock
        swayidle
        fuzzel
        foot
        wl-clipboard
        wtype
        python3
        yubikey-touch-detector
      ];

      services.swayidle = {
        enable = true;
        timeouts = [
          {
            timeout = 300;
            command = lock;
          }
          {
            timeout = 600;
            command = "${monitorsOff}";
            resumeCommand = "${monitorsOn}";
          }
          {
            timeout = 1800;
            command = "${pkgs.systemd}/bin/systemctl suspend";
          }
        ];
        events.before-sleep = lock;
      };

      xdg.configFile."swayosd/config.toml".source =
        (pkgs.formats.toml { }).generate "swayosd-config.toml"
          {
            server = {
              show_percentage = true;
              max_volume = 100;
            };
          };

      xdg.configFile."swaync/config.json".text = builtins.toJSON {
        positionX = "right";
        positionY = "top";
        control-center-margin-top = 10;
        control-center-margin-bottom = 10;
        control-center-margin-right = 10;
        control-center-margin-left = 0;
        notification-icon-size = 64;
        notification-body-image-height = 200;
        notification-body-image-width = 200;
        timeout = 3;
        timeout-low = 5;
        timeout-critical = 0;
        fit-to-screen = true;
        control-center-width = 400;
        control-center-height = 600;
        notification-window-width = 300;
        keyboard-shortcuts = true;
        image-visibility = "when-available";
        transition-time = 200;
        hide-on-clear = false;
        hide-on-action = true;
        script-fail-notify = true;
        widgets = [
          "title"
          "dnd"
          "notifications"
        ];
        widget-config = {
          title = {
            text = "Notifications";
            clear-all-button = true;
            button-text = "Clear All";
          };
          dnd.text = "Do Not Disturb";
          notifications.vexpand = true;
        };
      };

      services.cliphist = {
        enable = true;
        allowImages = true;
      };

      systemd.user.services = {
        polkit-agent = sessionService {
          description = "PolicyKit authentication agent";
          exec = "${pkgs.mate-polkit}/libexec/polkit-mate-authentication-agent-1";
        };

        waybar = sessionService {
          description = "Waybar";
          exec = "${pkgs.waybar}/bin/waybar";
          service.ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR2 $MAINPID";
        };

        swaync = sessionService {
          description = "Notification daemon";
          exec = "${pkgs.swaynotificationcenter}/bin/swaync";
          service = {
            Type = "dbus";
            BusName = "org.freedesktop.Notifications";
          };
        };

        swayosd = sessionService {
          description = "SwayOSD server";
          exec = "${pkgs.swayosd}/bin/swayosd-server";
        };

        yubikey-touch-detector = sessionService {
          description = "YubiKey touch notifications";
          exec = "${pkgs.yubikey-touch-detector}/bin/yubikey-touch-detector";
          service.Environment = [ "YUBIKEY_TOUCH_DETECTOR_LIBNOTIFY=true" ];
        };

        tailscale-systray = sessionService {
          description = "Tailscale tray";
          exec = "${pkgs.tailscale}/bin/tailscale systray";
        };

        # No WantedBy: toggled by Waybar's stay-awake button.
        sleep-inhibit = {
          Unit.Description = "Block automatic system suspend";
          Service.ExecStart = lib.escapeShellArgs [
            "${pkgs.systemd}/bin/systemd-inhibit"
            "--what=sleep"
            "--who=Waybar"
            "--why=Stay awake toggle is active"
            "--mode=block"
            "${pkgs.coreutils}/bin/sleep"
            "infinity"
          ];
        };
      };
    };
}
