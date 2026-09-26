{ config, inputs, ... }:
let
  inherit (config.meta) user;
  home = "/home/${user.name}";
  borgbaseHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGU0mISTyHBw9tBs6SuhSq8tvNM8m9eifQxM+88TowPO";

  secrets = hostName: {
    borg-passphrase.file = inputs.self + "/secrets/${hostName}/borg-passphrase.age";
    borg-ssh-key.file = inputs.self + "/secrets/${hostName}/borg-ssh-key.age";
  };

  # Settings both hosts share; each adds its sources and excludes.
  borgmaticSettings =
    {
      lib,
      hostName,
      repo,
      ssh,
      secrets,
    }:
    {
      repositories = [
        {
          path = "ssh://${repo}@${repo}.repo.borgbase.com/./repo";
          label = "borgbase";
        }
      ];
      # Limits pruning to this host.
      archive_name_format = "home-${hostName}-{now:%Y-%m-%dT%H:%M:%S.%f}";
      match_archives = "sh:home-${hostName}-*";

      encryption_passcommand = "cat ${secrets.borg-passphrase.path}";
      ssh_command = lib.concatStringsSep " " [
        "${ssh} -F /dev/null"
        "-i ${secrets.borg-ssh-key.path}"
        "-o IdentitiesOnly=yes"
        "-o BatchMode=yes"
        "-o StrictHostKeyChecking=yes"
        "-o UserKnownHostsFile=/etc/ssh/ssh_known_hosts"
      ];

      compression = "zstd,3";
      exclude_caches = true;
      retries = 3;
      retry_wait = 300;

      keep_daily = 30;
      keep_weekly = 12;
      keep_monthly = 24;
      keep_yearly = 3;
      checks = [
        {
          name = "repository";
          frequency = "1 month";
        }
        {
          name = "archives";
          frequency = "1 month";
        }
      ];
    };
in
{
  flake.modules.nixos.backup =
    { config, lib, ... }:
    {
      age.secrets = secrets config.networking.hostName;

      programs.ssh.knownHosts.borgbase = {
        hostNames = [ "asfr5z3s.repo.borgbase.com" ];
        publicKey = borgbaseHostKey;
      };

      services.borgmatic = {
        enable = true;
        configurations.home =
          borgmaticSettings {
            inherit lib;
            inherit (config.networking) hostName;
            repo = "asfr5z3s";
            ssh = "ssh";
            secrets = config.age.secrets;
          }
          // {
            source_directories = [
              home
              "/var/lib/lidarr"
              "/var/lib/slskd"
              "/var/lib/soularr"
              "/var/lib/private/listenbrainz-recommendations"
              "/var/lib/sbctl"
              "/etc/ssh/ssh_host_ed25519_key"
              "/etc/ssh/ssh_host_ed25519_key.pub"
              "/var/lib/tailscale"
              "/var/lib/bluetooth"
            ];
            # Lidarr writes its database continuously; back up a consistent dump
            # instead of the live file.
            sqlite_databases = [
              {
                name = "lidarr";
                path = "/var/lib/lidarr/lidarr.db";
              }
            ];
            exclude_patterns =
              map (path: "${home}/${path}") [
                ".cache"
                ".unsloth"
                ".npm"
                ".xlcore"
                "Downloads"
                ".local/share/Trash"
                ".local/share/containers/storage"
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
                ".var/app/ai.lmstudio.lm-studio"
                ".config/discord/Cache"
                ".config/discord/Code Cache"
                ".config/discord/GPUCache"
                "Developer/cports/bldroot"
                "Developer/cports/packages"
                "Developer/cports/sources"
                "Developer/orca/.zig-cache"
                "Developer/orca/zig-out"
                "Developer/qbz/crates/target"
              ]
              ++ [
                "sh:${home}/.var/app/*/cache"
                "sh:/var/lib/lidarr/lidarr.db*"
                "sh:/var/lib/lidarr/logs*"
                "/var/lib/lidarr/MediaCover"
              ];
          };
      };

      # The upstream unit loads an encrypted credential for the passphrase; agenix provides it instead.
      systemd.services.borgmatic.serviceConfig.LoadCredentialEncrypted = "";

      systemd.timers.borgmatic.timerConfig = {
        OnCalendar = [
          ""
          "*-*-* 13:00:00"
        ];
        RandomizedDelaySec = lib.mkForce "15m";
        Persistent = true;
      };

      services.snapper.configs.home = {
        SUBVOLUME = "/home";
        ALLOW_USERS = [ user.name ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
      };
    };

  flake.modules.darwin.backup =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      home = "/Users/${user.name}";
      settings =
        borgmaticSettings {
          inherit lib;
          inherit (config.networking) hostName;
          repo = "o0dskefv";
          ssh = "/usr/bin/ssh";
          secrets = config.age.secrets;
        }
        // {
          local_path = lib.getExe' pkgs.borgbackup "borg";
          # Some Apple app data stays unreadable even with Full Disk Access; skip it
          # with a warning in the log instead of failing the whole backup.
          borg_exit_codes = [
            {
              code = 104;
              treat_as = "warning";
            }
          ];
          source_directories = [
            home
            "/etc/ssh/ssh_host_ed25519_key"
            "/etc/ssh/ssh_host_ed25519_key.pub"
          ];
          exclude_patterns =
            map (path: "${home}/${path}") [
              ".cache"
              ".npm"
              ".Trash"
              "Downloads"
              "Applications/Home Manager Apps"
              "Library/Caches"
              "Library/Logs"
              "Library/Developer"
              "Library/Metadata/CoreSpotlight"
              # iCloud Drive; iCloud keeps it, and files not downloaded fail to read.
              "Library/Mobile Documents"
              "Library/Application Support/discord/Cache"
              "Library/Application Support/discord/Code Cache"
              "Library/Application Support/discord/GPUCache"
            ]
            ++ [
              "sh:${home}/Library/Containers/*/Data/Library/Caches"
              "sh:${home}/Library/Group Containers/*/Library/Caches"
              "sh:${home}/Library/Group Containers/*/Caches"
            ];
        };
      # Full Disk Access is granted to this binary. It spawns borgmatic and waits, so
      # borgmatic and borg inherit the grant; its path and contents stay the same
      # across borgmatic updates, so the grant survives them.
      launcher = pkgs.runCommandCC "borgmatic-launcher" { } ''
        mkdir -p $out/bin
        $CC -O2 -o $out/bin/borgmatic-launcher ${./_backup/launcher.c}
      '';
      launcherPath = "/usr/local/libexec/borgmatic-launcher";
    in
    {
      age.secrets = secrets config.networking.hostName;

      programs.ssh.knownHosts.borgbase = {
        hostNames = [ "o0dskefv.repo.borgbase.com" ];
        publicKey = borgbaseHostKey;
      };

      environment.systemPackages = [ pkgs.borgmatic ];
      environment.etc."borgmatic/config.yaml".source =
        (pkgs.formats.yaml { }).generate "borgmatic.yaml"
          settings;

      # Replaced only when it changes, which would need Full Disk Access again.
      system.activationScripts.postActivation.text = ''
        if ! cmp -s ${launcher}/bin/borgmatic-launcher ${launcherPath}; then
          mkdir -p ${dirOf launcherPath}
          install -m 0755 ${launcher}/bin/borgmatic-launcher ${launcherPath}
        fi
      '';

      launchd.daemons.borgmatic.serviceConfig = {
        ProgramArguments = [
          launcherPath
          "--verbosity"
          "1"
        ];
        # Runs at next wake if the Mac was asleep at 13:00.
        StartCalendarInterval = [
          {
            Hour = 13;
            Minute = 0;
          }
        ];
        StandardOutPath = "/var/log/borgmatic.log";
        StandardErrorPath = "/var/log/borgmatic.log";
        ProcessType = "Background";
        LowPriorityIO = true;
      };
    };
}
