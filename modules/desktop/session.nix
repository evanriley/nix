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
  inherit (config.flake.lib) mkScript umbrielPackage;
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
      desktopctl = lib.getExe (
        mkScript pkgs {
          name = "desktopctl";
          src = ./_scripts/desktopctl;
          runtimeInputs = [
            config.programs.btop.package
            config.programs.rmpc.package
          ]
          ++ (with pkgs; [
            (umbrielPackage pkgs)
            foot
            grim
            slurp
            wl-clipboard
          ]);
        }
      );
    in
    {
      dotfiles.config = [
        "foot"
        "fuzzel"
      ];
      home.file.".local/bin/desktopctl".source = desktopctl;

      home.packages = with pkgs; [
        fuzzel
        foot
        wl-clipboard
        wtype
        python3
        yubikey-touch-detector
      ];

      systemd.user.services = {
        yubikey-touch-detector = sessionService {
          description = "YubiKey touch notifications";
          exec = "${pkgs.yubikey-touch-detector}/bin/yubikey-touch-detector";
          service.Environment = [ "YUBIKEY_TOUCH_DETECTOR_LIBNOTIFY=true" ];
        };
      };
    };
}
