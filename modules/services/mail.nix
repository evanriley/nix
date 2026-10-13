{ config, inputs, ... }:
let
  inherit (config.meta) user;
  secret = name: {
    file = inputs.self + "/secrets/${name}.age";
    owner = user.name;
  };
in
{
  flake.modules.nixos.mail.age.secrets = {
    fastmail-mail = secret "fastmail-mail";
    fastmail-authinfo = secret "fastmail-authinfo";
  };

  flake.modules.darwin.mail.age.secrets = {
    fastmail-mail = secret "fastmail-mail";
    fastmail-authinfo = secret "fastmail-authinfo";
  };

  flake.modules.homeManager.mail =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      isLinux = pkgs.stdenv.hostPlatform.isLinux;
      mailLock = "\${XDG_RUNTIME_DIR:-$HOME/.cache}/mail-sync.lock";
      mailSync = pkgs.writeShellApplication {
        name = "mail-sync";
        runtimeInputs = [
          pkgs.flock
          pkgs.isync
          pkgs.mu
        ];
        text = ''
          exec flock "${mailLock}" -c 'mbsync -a && mu index'
        '';
      };
      mailNotify = pkgs.writeShellApplication {
        name = "mail-notify";
        runtimeInputs = [ pkgs.mu ] ++ lib.optional isLinux pkgs.libnotify;
        text = ''
          message=$(mu find --fields "f s" --sortfield=date --reverse --maxnum 1 'maildir:/fastmail/Inbox' 2>/dev/null || true)
          [ -n "$message" ] || message="New mail in INBOX"
          if [ "$(uname)" = Darwin ]; then
            /usr/bin/osascript - "Fastmail" "$message" <<'APPLESCRIPT' >/dev/null 2>&1 || true
          on run argv
            display notification (item 2 of argv) with title (item 1 of argv)
          end run
          APPLESCRIPT
          else
            notify-send --app-name "Fastmail" "Fastmail" "$message"
          fi
        '';
      };
      goimapnotifyConfig = pkgs.writeText "goimapnotify.yaml" ''
        configurations:
          - host: imap.fastmail.com
            port: 993
            tls: true
            tlsOptions:
              rejectUnauthorized: true
              starttls: false
            username: evan@evanriley.com
            passwordCMD: 'cat /run/agenix/fastmail-mail'
            boxes:
              - mailbox: INBOX
                onNewMail: '${lib.getExe mailSync}'
                onNewMailPost: '${lib.getExe mailNotify}'
      '';
    in
    {
      accounts.email = {
        maildirBasePath = "${config.home.homeDirectory}/.mail";
        certificatesFile = lib.mkIf (!isLinux) "/etc/ssl/cert.pem";
        accounts.fastmail = {
          primary = true;
          address = "evan@evanriley.com";
          realName = user.fullName;
          userName = "evan@evanriley.com";
          passwordCommand = "cat /run/agenix/fastmail-mail";
          imap = {
            host = "imap.fastmail.com";
            port = 993;
            tls.enable = true;
          };
          smtp = {
            host = "smtp.fastmail.com";
            port = 465;
            tls.enable = true;
          };
          mbsync = {
            enable = true;
            create = "maildir";
          };
          msmtp.enable = true;
          mu.enable = true;
          # The maildir folder names Fastmail exposes (not the IMAP-style
          # home-manager defaults).
          folders = {
            inbox = "Inbox";
            sent = "Sent";
            drafts = "Drafts";
            trash = "Trash";
          };
          aerc = {
            enable = true;
            extraAccounts = {
              # The maildir backend only rescans on check-mail; run the
              # flock-guarded sync script so aerc and the push/timer syncs
              # never race.
              check-mail-cmd = lib.getExe mailSync;
              check-mail-interval = 5;
              # Without this, :delete hard-deletes instead of moving to Trash.
              trash = "Trash";
            };
          };
        };
      };

      programs.mu.enable = true;
      programs.mbsync.enable = true;
      programs.msmtp.enable = true;

      # aerc reads the mbsync maildir and sends through msmtpq (from the msmtp
      # package). Failed sends queue here until `msmtpq -r` flushes them.
      programs.aerc = {
        enable = true;
        # accounts.conf lives in the store (0444); safe because the password
        # comes from passwordCommand (agenix), never written to the file.
        extraConfig.general.unsafe-accounts-conf = true;
        extraConfig.ui.sidebar-width = 25;
      };

      home.sessionVariables = {
        MSMTPQ_Q = "${config.xdg.dataHome}/msmtp/queue";
        MSMTPQ_LOG = "${config.xdg.dataHome}/msmtp/queue.log";
      };

      xdg.configFile."goimapnotify/goimapnotify.yaml".source = goimapnotifyConfig;

      systemd.user.services.mail-sync = lib.mkIf isLinux {
        Unit.Description = "Sync mail with mbsync and index it with mu";
        Service = {
          Type = "oneshot";
          Environment = "MUHOME=${config.programs.mu.home}";
          # The first full-account pull can take an hour; systemd's user manager
          # defaults to a 90s start timeout.
          TimeoutStartSec = "infinity";
          ExecStart = lib.getExe mailSync;
        };
      };

      systemd.user.timers.mail-sync = lib.mkIf isLinux {
        Unit.Description = "Sync mail every 5 minutes";
        Timer = {
          OnBootSec = "5min";
          OnUnitActiveSec = "5min";
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };

      launchd.agents.mail-sync = lib.mkIf (!isLinux) {
        enable = true;
        config = {
          ProgramArguments = [ (lib.getExe mailSync) ];
          EnvironmentVariables.MUHOME = config.programs.mu.home;
          StartInterval = 300;
          RunAtLoad = true;
        };
      };

      systemd.user.services.goimapnotify = lib.mkIf isLinux {
        Unit = {
          Description = "IMAP IDLE push mail for Fastmail";
          After = [ "network-online.target" ];
        };
        Service = {
          ExecStart = "${lib.getExe pkgs.goimapnotify} -conf ${goimapnotifyConfig}";
          Restart = "on-failure";
          RestartSec = "10s";
          Environment = [
            "MUHOME=${config.programs.mu.home}"
            "PATH=${lib.makeBinPath [ pkgs.coreutils ]}"
          ];
        };
        Install.WantedBy = [ "default.target" ];
      };

      launchd.agents.goimapnotify = lib.mkIf (!isLinux) {
        enable = true;
        config = {
          ProgramArguments = [
            (lib.getExe pkgs.goimapnotify)
            "-conf"
            (toString goimapnotifyConfig)
          ];
          EnvironmentVariables = {
            MUHOME = config.programs.mu.home;
            PATH = lib.makeBinPath [ pkgs.coreutils ];
          };
          KeepAlive = true;
          RunAtLoad = true;
        };
      };
    };
}
