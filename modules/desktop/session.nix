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
      home = config.home.homeDirectory;
    in
    {
      dotfiles.config = [
        "darkman"
        "foot"
        "fuzzel"
        "gtk-3.0"
        "gtk-4.0"
        "niri"
        "swaync"
        "swayosd"
        "waybar"
        "xdg-desktop-portal"
      ];
      dotfiles.bin = [ "desktopctl" ];
      dotfiles.share = [ "darkman" ];

      home.packages = with pkgs; [
        waybar
        swaynotificationcenter
        swayosd
        darkman
        swaylock
        swayidle
        swaybg
        fuzzel
        foot
        grim
        slurp
        wl-clipboard
        wtype
        libnotify
        python3
      ];

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
          description = "Sway Notification Center";
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

        darkman = sessionService {
          description = "Darkman light/dark switching";
          exec = "${pkgs.darkman}/bin/darkman run";
          service = {
            Type = "dbus";
            BusName = "nl.whynothugo.darkman";
          };
        };

        idle = sessionService {
          description = "Idle lock, blank and suspend";
          exec = "${home}/.local/bin/desktopctl idle";
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
