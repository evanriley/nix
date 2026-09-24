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
        "swaync"
        "swayosd"
        "waybar"
      ];
      home.file.".local/bin/desktopctl".source = lib.getExe (
        mkScript pkgs {
          name = "desktopctl";
          src = ./_scripts/desktopctl;
          runtimeInputs = with pkgs; [
            niri
            foot
            btop
            rmpc
            fuzzel
            swaylock
            systemd
            procps
          ];
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
