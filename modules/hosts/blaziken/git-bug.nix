{
  ...
}:
let
  domain = "maybemaybe.lol";
  origin = "/var/lib/gerrit/git/maybe.git";
in
{
  flake.modules.nixos.blaziken =
    { config, pkgs, ... }:
    let
      gitBug = pkgs.git-bug;
    in
    {
      # git-bug 0.11's repository browser cannot read bare repositories, so the
      # web UI runs on a clone of the monorepo. Issues are stored in the
      # refs/bugs and refs/identities namespaces. git-bug pull and push sync them
      # with the canonical Gerrit repository and merge diverged edits.
      systemd.services.git-bug-webui = {
        description = "git-bug web UI";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        startLimitIntervalSec = 300;
        startLimitBurst = 5;
        path = [
          pkgs.git
          pkgs.gawk
        ];

        preStart = ''
          set -e
          if [ ! -e /var/lib/git-bug/maybe/.git ]; then
            git clone ${origin} /var/lib/git-bug/maybe
            git -C /var/lib/git-bug/maybe checkout --detach
            git -C /var/lib/git-bug/maybe fetch -q origin \
              'refs/bugs/*:refs/bugs/*' \
              'refs/identities/*:refs/identities/*'
          fi
          cd /var/lib/git-bug/maybe
          # Detached so fetching into refs/heads is allowed.
          git checkout -q --detach
          git fetch -q --prune origin '+refs/heads/*:refs/heads/*'
          git checkout -q --detach refs/heads/main
          # go-git cannot read packs written by Gerrit's JGit receive path;
          # consolidate them with the system git on every restart.
          git repack -adq
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
          ${gitBug}/bin/git-bug push origin
        '';

        serviceConfig = {
          User = "gerrit";
          Group = "gerrit";
          StateDirectory = "git-bug";
          StateDirectoryMode = "750";
          # The clone is created in preStart, after systemd has already applied
          # WorkingDirectory, so the service itself changes directory.
          ExecStart = "${pkgs.bash}/bin/bash -c 'cd /var/lib/git-bug/maybe && exec ${gitBug}/bin/git-bug webui --bind 127.0.0.1 --port 8083 --no-open'";
          # Periodic restarts rebuild the cache and pick up bugs pushed by
          # other machines; preStart pulls and merges them on the way back up.
          Restart = "always";
          RestartSec = "30s";
          RuntimeMaxSec = "1h";
        };
      };

      systemd.services.git-bug-sync = {
        description = "Push git-bug refs back to the Gerrit repository";
        path = [ pkgs.git ];
        after = [ "git-bug-webui.service" ];
        serviceConfig = {
          User = "gerrit";
          Group = "gerrit";
          Type = "oneshot";
        };
        script = ''
          [ -d /var/lib/git-bug/maybe/.git ] || exit 0
          cd /var/lib/git-bug/maybe
          status=0
          report=$(git push --porcelain ${origin} \
            'refs/bugs/*:refs/bugs/*' \
            'refs/identities/*:refs/identities/*') || status=$?
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
        settings.TARGET = "http://127.0.0.1:8083";
      };

      services.nginx.virtualHosts."bugs.${domain}" = {
        forceSSL = true;
        useACMEHost = domain;
        basicAuthFile = config.age.secrets.gerrit-htpasswd.path;
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
