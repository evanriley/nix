{ config, ... }:
let
  inherit (config.meta) user;
  inherit (config.flake.lib) sessionService;
  replaysDir = "Videos/Replays";
in
{
  flake.modules.nixos.gaming =
    { config, pkgs, ... }:
    let
      home = config.users.users.${user.name}.home;
    in
    {
      programs.steam.enable = true;
      # No capSysNice: Steam's sandbox then refuses to start gamescope (nixpkgs#351516).
      programs.gamescope.enable = true;

      programs.gamemode.enable = true;
      users.users.${user.name}.extraGroups = [ "gamemode" ];

      programs.gpu-screen-recorder.enable = true;

      environment.systemPackages = [ pkgs.faugus-launcher ];

      boot.kernelModules = [ "ntsync" ];
      services.udev.extraRules = ''
        KERNEL=="ntsync", MODE="0666"
      '';

      boot.kernel.sysctl."kernel.split_lock_mitigate" = 0;

      services.borgmatic.configurations.home.exclude_patterns = map (path: "${home}/${path}") [
        ".local/share/Steam/appcache"
        ".local/share/Steam/clientui"
        ".local/share/Steam/depotcache"
        ".local/share/Steam/logs"
        ".local/share/Steam/package"
        ".local/share/Steam/steamrt32"
        ".local/share/Steam/steamrt64"
        ".local/share/Steam/steamui"
        ".local/share/Steam/ubuntu12_32"
        ".local/share/Steam/ubuntu12_64"
        ".local/share/Steam/config/htmlcache"
        ".local/share/Steam/steamapps/common"
        ".local/share/Steam/steamapps/downloading"
        ".local/share/Steam/steamapps/shadercache"
        ".local/share/Steam/steamapps/temp"
        ".local/share/Steam/steamapps/workshop"
        "Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/Data"
        replaysDir
      ];
    };

  flake.modules.homeManager.gaming =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      replayDir = "${config.home.homeDirectory}/${replaysDir}";
      sizeArg = lib.optionalString (config.gaming.replay.size != null) "-s ${config.gaming.replay.size}";
      notifySaved = pkgs.writeShellScript "replay-saved" ''
        exec ${pkgs.libnotify}/bin/notify-send --app-name=Replay "Replay saved" "$1"
      '';
    in
    {
      options.gaming.replay.size = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "2560x1440";
        description = "Replay buffer resolution; null records at the monitor's size.";
      };

      config = {
        # Shift+Print in niri saves the buffer; the system module installs the KMS capture wrapper.
        systemd.user.services.gpu-screen-recorder-replay = sessionService {
          description = "GPU Screen Recorder replay buffer";
          # AV1 plays in Firefox and Discord, unlike HEVC.
          exec = "/run/current-system/sw/bin/gpu-screen-recorder -w screen ${sizeArg} -f 60 -k av1 -bm cbr -q 40000 -r 60 -c mkv -a default_output -sc ${notifySaved} -o ${replayDir}";
          service.ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${replayDir}";
        };

        # Steam and Faugus both list compatibilitytools.d. Not named GE-Proton: umu
        # treats that name as "download the latest GE-Proton".
        home.file.".local/share/Steam/compatibilitytools.d/GE-Proton-Nix".source =
          pkgs.proton-ge-bin.steamcompattool;

        home.packages = [ pkgs.wowup-cf ];

        # Not niri spawn-at-startup: it dies in a race at login and niri discards its output.
        systemd.user.services.steam = sessionService {
          description = "Steam";
          exec = "/run/current-system/sw/bin/steam -silent";
        };

        programs.mangohud = {
          enable = true;
          settings = {
            toggle_hud = "Shift_R+F12";
            position = "top-left";
            fps = true;
            frametime = true;
            frame_timing = true;
            gpu_stats = true;
            gpu_temp = true;
            gpu_power = true;
            cpu_stats = true;
            cpu_temp = true;
            ram = true;
            vram = true;
          };
        };
      };
    };
}
