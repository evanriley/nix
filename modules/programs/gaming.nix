{ config, inputs, ... }:
let
  inherit (config.meta) user secrets;
  inherit (config.flake.lib) sessionService fetchPin pinVersion;
  replaysDir = "Videos/Replays";
in
{
  flake.modules.nixos.gaming =
    { config, pkgs, ... }:
    let
      home = config.users.users.${user.name}.home;
    in
    {
      age.secrets.craftplan-anthropic-key = {
        file = secrets + "/cinderace/craftplan-anthropic-key.age";
        owner = user.name;
      };

      programs.steam.enable = true;
      # No capSysNice: Steam's sandbox then refuses to start gamescope (nixpkgs#351516).
      programs.gamescope.enable = true;

      programs.gamemode.enable = true;
      users.users.${user.name}.extraGroups = [ "gamemode" ];

      programs.gpu-screen-recorder.enable = true;

      environment.systemPackages = [
        pkgs.faugus-launcher
        pkgs.xivlauncher
      ];

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

      craftplanDir = "%h/Developer/craftplan";
      craftplanSnapshotService =
        { description, scope }:
        {
          Unit = {
            Description = description;
            ConditionPathExists = "${craftplanDir}/gold/__main__.py";
            OnSuccess = [
              "craftplan-alerts.service"
              "craftplan-postqueue.service"
              "craftplan-route.service"
              "craftplan-track-record.service"
            ];
          };
          Service = {
            Type = "oneshot";
            WorkingDirectory = craftplanDir;
            ExecStart = "${pkgs.python314}/bin/python3 -m gold snapshot ${scope}";
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };

      tradeskillmasterVersion = pinVersion ./tradeskillmaster.json;
      tradeskillmasterSrc = fetchPin pkgs ./tradeskillmaster.json "appimage";
      tradeskillmasterContents = pkgs.appimageTools.extract {
        pname = "tradeskillmaster";
        version = tradeskillmasterVersion;
        src = tradeskillmasterSrc;
      };
      tradeskillmaster = pkgs.appimageTools.wrapType2 {
        pname = "tradeskillmaster";
        version = tradeskillmasterVersion;
        src = tradeskillmasterSrc;
        extraInstallCommands = ''
          install -Dm444 ${tradeskillmasterContents}/TradeSkillMaster.desktop \
            $out/share/applications/TradeSkillMaster.desktop
          substituteInPlace $out/share/applications/TradeSkillMaster.desktop \
            --replace-fail 'Exec=AppRun' 'Exec=tradeskillmaster'
          mkdir -p $out/share/icons
          cp -r --no-preserve=mode ${tradeskillmasterContents}/usr/share/icons/hicolor $out/share/icons/hicolor
        '';
        meta = {
          description = "TradeSkillMaster desktop app for World of Warcraft";
          homepage = "https://www.tradeskillmaster.com";
          license = lib.licenses.unfree;
          platforms = [ "x86_64-linux" ];
          mainProgram = "tradeskillmaster";
        };
      };

      wagoappVersion = pinVersion ./wagoapp.json;
      wagoappSrc = fetchPin pkgs ./wagoapp.json "appimage";
      wagoappContents = pkgs.appimageTools.extract {
        pname = "wagoapp";
        version = wagoappVersion;
        src = wagoappSrc;
      };
      wagoapp = pkgs.appimageTools.wrapType2 {
        pname = "wagoapp";
        version = wagoappVersion;
        src = wagoappSrc;
        extraInstallCommands = ''
          install -Dm444 ${wagoappContents}/WagoApp.desktop \
            $out/share/applications/WagoApp.desktop
          substituteInPlace $out/share/applications/WagoApp.desktop \
            --replace-fail 'Exec=AppRun' 'Exec=wagoapp'
          install -Dm444 ${wagoappContents}/WagoApp.png $out/share/pixmaps/WagoApp.png
        '';
        meta = {
          description = "Wago addon and WeakAura manager for World of Warcraft";
          homepage = "https://addons.wago.io/app";
          license = lib.licenses.unfree;
          platforms = [ "x86_64-linux" ];
          mainProgram = "wagoapp";
        };
      };
    in
    {
      options.gaming.replay.enable = lib.mkEnableOption "the GPU Screen Recorder replay buffer";

      options.gaming.replay.size = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "2560x1440";
        description = "Replay buffer resolution; null records at the monitor's size.";
      };

      config = {
        # Shift+Print saves the buffer; the system module installs the KMS capture wrapper.
        systemd.user.services.gpu-screen-recorder-replay =
          lib.mkIf config.gaming.replay.enable
            (sessionService {
              description = "GPU Screen Recorder replay buffer";
              # AV1 plays in Firefox and Discord, unlike HEVC.
              exec = "/run/current-system/sw/bin/gpu-screen-recorder -w screen ${sizeArg} -f 60 -k av1 -bm cbr -q 40000 -r 60 -c mkv -a default_output -sc ${notifySaved} -o ${replayDir}";
              service.ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${replayDir}";
            });

        systemd.user.services.craftplan-snapshot = craftplanSnapshotService {
          description = "Snapshot tracked auction house prices";
          scope = "--tracked";
        };

        systemd.user.services.craftplan-snapshot-full = craftplanSnapshotService {
          description = "Snapshot the full auction house market";
          scope = "--full";
        };

        systemd.user.services.craftplan-alerts = {
          Unit = {
            Description = "Check craftplan gold alerts";
            ConditionPathExists = "${craftplanDir}/gold/alerts_engine.py";
          };
          Service = {
            Type = "oneshot";
            WorkingDirectory = craftplanDir;
            ExecStart = "${pkgs.python314}/bin/python3 -m gold.alerts check";
            Environment = "PATH=${pkgs.libnotify}/bin";
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };

        systemd.user.services.craftplan-postqueue = {
          Unit = {
            Description = "Write the craftplan auction house post queue";
            ConditionPathExists = "${craftplanDir}/gold/postqueue.py";
          };
          Service = {
            Type = "oneshot";
            WorkingDirectory = craftplanDir;
            ExecStart = "${pkgs.python314}/bin/python3 -m gold postqueue";
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };

        systemd.user.services.craftplan-postqueue-refresh = {
          Unit = {
            Description = "Rewrite the craftplan post queue when its inputs change";
            ConditionPathExists = "${craftplanDir}/gold/postqueue.py";
          };
          Service = {
            Type = "oneshot";
            WorkingDirectory = craftplanDir;
            ExecStart = "${pkgs.python314}/bin/python3 -m gold postqueue --if-changed";
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };

        systemd.user.services.craftplan-route = {
          Unit = {
            Description = "Rewrite the craftplan in-game gathering routes when they change";
            ConditionPathExists = "${craftplanDir}/gold/routefile.py";
          };
          Service = {
            Type = "oneshot";
            WorkingDirectory = craftplanDir;
            ExecStart = "${pkgs.python314}/bin/python3 -m gold route --if-changed";
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };

        systemd.user.services.craftplan-track-record = {
          Unit = {
            Description = "Log the craftplan Today recommendations";
            ConditionPathExists = "${craftplanDir}/gold/trackrecord.py";
          };
          Service = {
            Type = "oneshot";
            WorkingDirectory = craftplanDir;
            ExecStart = "${pkgs.python314}/bin/python3 -m gold track record";
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };

        systemd.user.services.craftplan-track-score = {
          Unit = {
            Description = "Score the craftplan recommendations past their horizon";
            ConditionPathExists = "${craftplanDir}/gold/trackrecord.py";
          };
          Service = {
            Type = "oneshot";
            WorkingDirectory = craftplanDir;
            ExecStart = "${pkgs.python314}/bin/python3 -m gold track score";
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };

        systemd.user.services.craftplan-web = {
          Unit = {
            Description = "Serve the craftplan gold web UI";
            ConditionPathExists = "${craftplanDir}/gold/__main__.py";
          };
          Service = {
            WorkingDirectory = craftplanDir;
            ExecStart = "${pkgs.python314}/bin/python3 -m gold serve --reload";
            Environment = "CRAFTPLAN_ANTHROPIC_KEY_FILE=/run/agenix/craftplan-anthropic-key";
            Restart = "always";
            RestartSec = 2;
            Nice = 10;
          };
          Install.WantedBy = [ "default.target" ];
        };

        systemd.user.timers.craftplan-snapshot = {
          Unit.Description = "Snapshot tracked auction house prices hourly";
          Timer = {
            OnCalendar = "*:35";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };

        systemd.user.timers.craftplan-route = {
          Unit.Description = "Check the craftplan gathering routes every 5 minutes";
          Timer.OnCalendar = "*:0/5";
          Install.WantedBy = [ "timers.target" ];
        };

        systemd.user.timers.craftplan-postqueue-refresh = {
          Unit.Description = "Check the craftplan post queue inputs every 5 minutes";
          Timer.OnCalendar = "*:0/5";
          Install.WantedBy = [ "timers.target" ];
        };

        systemd.user.timers.craftplan-track-score = {
          Unit.Description = "Score the craftplan recommendations every 6 hours";
          Timer = {
            OnCalendar = "00/6:50";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };

        systemd.user.timers.craftplan-snapshot-full = {
          Unit.Description = "Snapshot the full auction house market daily";
          Timer = {
            OnCalendar = "*-*-* 04:45:00";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };

        # Steam and Faugus both list compatibilitytools.d. Not named GE-Proton: umu
        # treats that name as "download the latest GE-Proton".
        home.file.".local/share/Steam/compatibilitytools.d/GE-Proton-Nix".source =
          pkgs.proton-ge-bin.steamcompattool;

        # In home.packages, not manta's NixOS module: CI evaluates the system
        # configurations and cannot fetch the private repository.
        home.packages = [
          pkgs.wowup-cf
          tradeskillmaster
          wagoapp
          inputs.manta.packages.${pkgs.stdenv.hostPlatform.system}.default
        ];

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
