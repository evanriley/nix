{ config, inputs, ... }:
let
  inherit (config.meta) user;
  borgbaseHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGU0mISTyHBw9tBs6SuhSq8tvNM8m9eifQxM+88TowPO";
  repos = {
    cinderace = "asfr5z3s";
    ninetales = "o0dskefv";
  };

  repo = hostName: repos.${hostName};

  secretsAndHostKey =
    { config, ... }:
    let
      inherit (config.networking) hostName;
    in
    {
      age.secrets = {
        borg-passphrase.file = inputs.self + "/secrets/${hostName}/borg-passphrase.age";
        borg-ssh-key.file = inputs.self + "/secrets/${hostName}/borg-ssh-key.age";
      };

      programs.ssh.knownHosts.borgbase = {
        hostNames = [ "${repo hostName}.repo.borgbase.com" ];
        publicKey = borgbaseHostKey;
      };
    };

  settings =
    {
      config,
      lib,
      ssh,
    }:
    let
      inherit (config.networking) hostName;
      secrets = config.age.secrets;
    in
    {
      repositories = [
        {
          path = "ssh://${repo hostName}@${repo hostName}.repo.borgbase.com/./repo";
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

      source_directories = [
        config.users.users.${user.name}.home
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
      ];
    };
in
{
  flake.modules.nixos.backup =
    { config, lib, ... }:
    let
      home = config.users.users.${user.name}.home;
    in
    {
      imports = [ secretsAndHostKey ];

      services.borgmatic = {
        enable = true;
        configurations.home =
          settings {
            inherit config lib;
            ssh = "ssh";
          }
          // {
            exclude_patterns =
              map (path: "${home}/${path}") [
                ".cache"
                ".npm"
                "Downloads"
                ".local/share/Trash"
                ".config/discord/Cache"
                ".config/discord/Code Cache"
                ".config/discord/GPUCache"
              ]
              ++ [ "sh:${home}/.var/app/*/cache" ];
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
    };

  flake.modules.darwin.backup =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      home = config.users.users.${user.name}.home;
      borgmaticConfig =
        settings {
          inherit config lib;
          ssh = "/usr/bin/ssh";
        }
        // {
          local_path = lib.getExe' pkgs.borgbackup "borg";
          borg_exit_codes = [
            {
              code = 104;
              treat_as = "warning";
            }
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
      # Holds the Full Disk Access grant: it must spawn borgmatic (not exec) and stay
      # byte-identical, or the grant is lost.
      launcher = pkgs.runCommandCC "borgmatic-launcher" { } ''
        mkdir -p $out/bin
        $CC -O2 -o $out/bin/borgmatic-launcher ${./_backup/launcher.c}
      '';
      launcherPath = "/usr/local/libexec/borgmatic-launcher";
    in
    {
      imports = [ secretsAndHostKey ];

      environment.systemPackages = [ pkgs.borgmatic ];
      environment.etc."borgmatic/config.yaml".source =
        (pkgs.formats.yaml { }).generate "borgmatic.yaml"
          borgmaticConfig;

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
        StartCalendarInterval = [
          {
            Hour = 20;
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
