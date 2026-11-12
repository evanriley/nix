{ config, ... }:
let
  inherit (config.meta) user secrets domain;
  origin = "/var/lib/gerrit/git/maybe.git";
  editClone = "/var/lib/git-bug/maybe";
  publicClone = "/var/lib/git-bug-public/public";
  editPort = 8083;
  publicPort = 8084;
  oauth2ProxyPort = 4180;
  oauth2ProxyClientSecret = "/run/oauth2-proxy/client-secret";
in
{
  flake.modules.nixos.blaziken =
    { config, pkgs, ... }:
    let
      gitBug = pkgs.git-bug.overrideAttrs (old: {
        src = pkgs.applyPatches {
          inherit (old) src;
          patches = [ ./git-bug-edit-comment.patch ];
        };
      });

      refreshClone = clone: ''
        if [ ! -e ${clone}/.git ]; then
          git clone ${origin} ${clone}
          git -C ${clone} checkout --detach
          git -C ${clone} fetch -q origin \
            'refs/bugs/*:refs/bugs/*' \
            'refs/identities/*:refs/identities/*'
        fi
        cd ${clone}
        # Detached so fetching into refs/heads is allowed.
        git checkout -q --detach
        git fetch -q --prune origin '+refs/heads/*:refs/heads/*'
        git checkout -q --detach refs/heads/main
        # go-git cannot read packs written by Gerrit's JGit receive path;
        # consolidate them with the system git on every restart.
        git repack -adq
      '';

      safeDirectory = path: {
        GIT_CONFIG_COUNT = "1";
        GIT_CONFIG_KEY_0 = "safe.directory";
        GIT_CONFIG_VALUE_0 = path;
      };

      sandbox = {
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        ProtectClock = true;
        ProtectHostname = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged @resources"
        ];
        UMask = "0027";
        TemporaryFileSystem = "/var/lib/gerrit:ro";
      };

      webui =
        {
          description,
          user,
          clone,
          port,
          extraArgs,
          preStart,
          restartSec,
          runtimeMaxSec,
        }:
        {
          inherit description preStart;
          environment = safeDirectory origin;
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          startLimitIntervalSec = 300;
          startLimitBurst = 5;
          path = [
            pkgs.git
            pkgs.gawk
          ];
          serviceConfig = {
            User = user;
            Group = user;
            SupplementaryGroups = [ "gerrit" ];
            StateDirectory = user;
            StateDirectoryMode = "750";
            BindReadOnlyPaths = [ origin ];
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
            IPAddressDeny = "any";
            IPAddressAllow = "localhost";
            # The clone is created in preStart, after systemd has already applied
            # WorkingDirectory, so the service itself changes directory.
            ExecStart = "${pkgs.bash}/bin/bash -c 'cd ${clone} && exec ${gitBug}/bin/git-bug webui --bind 127.0.0.1 --port ${toString port} --no-open${extraArgs}'";
            # Periodic restarts pick up bugs pushed by other machines; preStart
            # pulls them on the way back up.
            Restart = "always";
            RestartSec = restartSec;
            RuntimeMaxSec = runtimeMaxSec;
          }
          // sandbox;
        };

      restartPublicWebuiIfPushed = pkgs.writeShellScript "restart-git-bug-webui-public-if-pushed" ''
        if [ -e "$RUNTIME_DIRECTORY/pushed" ]; then
          ${config.systemd.package}/bin/systemctl try-restart --no-block git-bug-webui-public.service
        fi
      '';
    in
    {
      users.users.git-bug = {
        isSystemUser = true;
        group = "git-bug";
      };
      users.groups.git-bug = { };
      users.users.git-bug-public = {
        isSystemUser = true;
        group = "git-bug-public";
      };
      users.groups.git-bug-public = { };

      systemd.tmpfiles.rules = [ "R /var/lib/git-bug/public - - - -" ];

      # git-bug 0.11's repository browser cannot read bare repositories, so the
      # web UI runs on a clone of the monorepo. Issues are stored in the
      # refs/bugs and refs/identities namespaces. git-bug pull merges diverged
      # edits from the canonical Gerrit repository; git-bug-sync pushes them back
      # with the system git, because go-git's push reads the remote's JGit packs
      # and fails.
      systemd.services.git-bug-webui = webui {
        description = "git-bug web UI";
        user = "git-bug";
        clone = editClone;
        port = editPort;
        extraArgs = "";
        restartSec = "30s";
        runtimeMaxSec = "1h";
        preStart = ''
          ${refreshClone editClone}
          git config user.name "Evan Riley"
          git config user.email "evan@evanriley.com"
          if [ -z "$(${gitBug}/bin/git-bug user ls 2>/dev/null)" ]; then
            ${gitBug}/bin/git-bug user new --non-interactive \
              --name "Evan Riley" \
              --email evan@evanriley.com
          elif ! git config --get git-bug.identity >/dev/null; then
            # A fresh clone has the identities but no default identity set.
            ID=$(${gitBug}/bin/git-bug user ls | awk '/Evan Riley/ {print $1; exit}')
            ${gitBug}/bin/git-bug user adopt "$ID"
          fi
          ${gitBug}/bin/git-bug pull origin
        '';
      };

      # git-bug's cache lock allows one process per clone, so the read-only
      # instance has its own clone. It never writes, so it needs no identity.
      systemd.services.git-bug-webui-public = webui {
        description = "git-bug read-only web UI";
        user = "git-bug-public";
        clone = publicClone;
        port = publicPort;
        extraArgs = " --read-only";
        restartSec = "1s";
        runtimeMaxSec = "10min";
        preStart = ''
          ${refreshClone publicClone}
          ${gitBug}/bin/git-bug pull origin
        '';
      };

      systemd.services.git-bug-sync = {
        description = "Push git-bug refs back to the Gerrit repository";
        path = [ pkgs.git ];
        environment = safeDirectory editClone;
        after = [ "git-bug-webui.service" ];
        serviceConfig = {
          User = "gerrit";
          Group = "gerrit";
          SupplementaryGroups = [ "git-bug" ];
          Type = "oneshot";
          RuntimeDirectory = "git-bug-sync";
          ExecStartPost = "+${restartPublicWebuiIfPushed}";
          BindPaths = [ origin ];
          PrivateNetwork = true;
          RestrictAddressFamilies = [ "AF_UNIX" ];
        }
        // sandbox;
        script = ''
          [ -d ${editClone}/.git ] || exit 0
          cd ${editClone}
          status=0
          report=$(git push --porcelain ${origin} \
            'refs/bugs/*:refs/bugs/*' \
            'refs/identities/*:refs/identities/*') || status=$?
          if printf '%s\n' "$report" | grep -q $'^[ *+-]\t'; then
            touch "$RUNTIME_DIRECTORY/pushed"
          fi
          [ "$status" -eq 0 ] && exit 0
          failed=$(printf '%s\n' "$report" | grep $'^!\t' || true)
          if [ -n "$failed" ] && ! printf '%s\n' "$failed" | grep -qvE '\[rejected\] \((non-fast-forward|fetch first)\)$'; then
            echo "Origin rejected diverged git-bug refs; expected git-bug-webui to merge them on its next restart:" >&2
            printf '%s\n' "$failed" >&2
            exit 0
          fi
          printf '%s\n' "$report" >&2
          exit "$status"
        '';
      };

      systemd.timers.git-bug-sync = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitActiveSec = "10min";
          Unit = "git-bug-sync.service";
        };
      };

      services.anubis.instances.bugs = {
        group = "nginx";
        settings.TARGET = "http://127.0.0.1:${toString editPort}";
      };

      services.anubis.instances.bugs-public = {
        group = "nginx";
        settings.TARGET = "http://127.0.0.1:${toString publicPort}";
      };

      age.secrets.git-bug-oidc-secret.file = secrets + "/blaziken/git-bug-oidc-secret.age";
      age.secrets.oauth2-proxy-cookie-secret.file = secrets + "/blaziken/oauth2-proxy-cookie-secret.age";

      services.oauth2-proxy = {
        enable = true;
        httpAddress = "http://127.0.0.1:${toString oauth2ProxyPort}";
        provider = "oidc";
        oidcIssuerUrl = "https://id.${domain}";
        clientID = "bce6d24c-8e70-4520-a5b6-adca7160fa77";
        redirectURL = "https://bugs-edit.${domain}/oauth2/callback";
        approvalPrompt = "auto";
        email.addresses = user.email;
        reverseProxy = true;
        trustedProxyIP = [ "127.0.0.1" ];
        cookie.secretFile = config.age.secrets.oauth2-proxy-cookie-secret.path;
        extraConfig.client-secret-file = oauth2ProxyClientSecret;
        nginx = {
          domain = "bugs-edit.${domain}";
          virtualHosts."bugs-edit.${domain}" = { };
        };
      };

      systemd.services.oauth2-proxy = {
        after = [
          "nginx.service"
          "pocket-id.service"
        ];
        wants = [
          "nginx.service"
          "pocket-id.service"
        ];
        # oauth2-proxy exits when Pocket ID's discovery document is unreachable.
        startLimitIntervalSec = 0;
        serviceConfig = {
          RestartSec = "5s";
          RuntimeDirectory = "oauth2-proxy";
          RuntimeDirectoryMode = "700";
          LoadCredential = [ "git-bug-oidc-secret:${config.age.secrets.git-bug-oidc-secret.path}" ];
        };
        # oauth2-proxy sends the client secret file verbatim, trailing newline
        # included.
        preStart = ''
          oidc_secret="$(< "$CREDENTIALS_DIRECTORY/git-bug-oidc-secret")"
          if [[ ! "$oidc_secret" =~ ^[A-Za-z0-9]+$ ]]; then
            echo "${config.age.secrets.git-bug-oidc-secret.path} is not an alphanumeric client secret; expected the secret Pocket ID shows for the git-bug client. Re-encrypt git-bug-oidc-secret.age with it." >&2
            exit 1
          fi
          umask 077
          printf '%s' "$oidc_secret" > ${oauth2ProxyClientSecret}
        '';
        restartTriggers = [
          (builtins.hashFile "sha256" config.age.secrets.git-bug-oidc-secret.file)
          (builtins.hashFile "sha256" config.age.secrets.oauth2-proxy-cookie-secret.file)
        ];
      };

      services.nginx.virtualHosts."bugs.${domain}" = {
        forceSSL = true;
        useACMEHost = domain;
        locations."/".proxyPass = "http://unix:/run/anubis/anubis-bugs-public/anubis.sock";
        locations."= /login".return = "302 https://bugs-edit.${domain}/";
      };

      services.nginx.virtualHosts."bugs-edit.${domain}" = {
        forceSSL = true;
        useACMEHost = domain;
        locations."/" = {
          proxyPass = "http://unix:/run/anubis/anubis-bugs/anubis.sock";
          proxyWebsockets = true;
        };
      };

      services.nginx.virtualHosts."b.${domain}" = {
        forceSSL = true;
        useACMEHost = domain;
        locations."= /".return = "302 https://bugs.${domain}/_/issues";
        locations."~ ^/([0-9a-f]+)/?$".return = "302 https://bugs.${domain}/_/issues/$1";
        locations."/".return = "404";
      };
    };
}
