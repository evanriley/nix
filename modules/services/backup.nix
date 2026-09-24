{ config, inputs, ... }:
let
  inherit (config.meta) user;
  home = "/home/${user.name}";
  borgbase = "fjz8475g.repo.borgbase.com";
in
{
  flake.modules.nixos.backup =
    { config, lib, ... }:
    {
      age.secrets = {
        borg-passphrase.file = inputs.self + "/secrets/${config.networking.hostName}/borg-passphrase.age";
        borg-ssh-key.file = inputs.self + "/secrets/${config.networking.hostName}/borg-ssh-key.age";
      };

      programs.ssh.knownHosts.borgbase = {
        hostNames = [ borgbase ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGU0mISTyHBw9tBs6SuhSq8tvNM8m9eifQxM+88TowPO";
      };

      services.borgmatic = {
        enable = true;
        configurations.home = {
          source_directories = [ home ];
          repositories = [
            {
              path = "ssh://fjz8475g@${borgbase}/./repo";
              label = "borgbase";
            }
          ];
          # Limits pruning to this host; pre-NixOS archives are home-cinderance-*.
          archive_name_format = "home-${config.networking.hostName}-{now:%Y-%m-%dT%H:%M:%S.%f}";
          match_archives = "sh:home-${config.networking.hostName}-*";

          encryption_passcommand = "cat ${config.age.secrets.borg-passphrase.path}";
          ssh_command = lib.concatStringsSep " " [
            "ssh -F /dev/null"
            "-i ${config.age.secrets.borg-ssh-key.path}"
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
            ++ [ "sh:${home}/.var/app/*/cache" ];
        };
      };

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
}
