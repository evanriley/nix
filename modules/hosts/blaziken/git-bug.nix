{
  ...
}:
let
  domain = "maybemaybe.lol";
  origin = "/var/lib/gerrit/git/maybe.git";
in
{
  flake.modules.nixos.blaziken =
    { pkgs, ... }:
    let
      gitBug = pkgs.git-bug;
    in
    {
      # git-bug 0.11's repository browser cannot read bare repositories, so the
      # web UI runs on a clone of the monorepo. Issues are stored in the
      # refs/bugs and refs/identities namespaces, which sync both ways with the
      # canonical Gerrit repository via plain git.
      systemd.services.git-bug-webui = {
        description = "git-bug web UI";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        path = [
          pkgs.git
          pkgs.gawk
        ];

        preStart = ''
          set -e
          if [ ! -e /var/lib/git-bug/maybe/.git ]; then
            git clone ${origin} /var/lib/git-bug/maybe
            git -C /var/lib/git-bug/maybe checkout --detach
          fi
          cd /var/lib/git-bug/maybe
          # Detached so fetching into refs/heads is allowed.
          git checkout -q --detach
          git push -q ${origin} \
            'refs/bugs/*:refs/bugs/*' \
            'refs/identities/*:refs/identities/*' || true
          git fetch -q --prune origin '+refs/heads/*:refs/heads/*' || true
          git fetch -q origin \
            '+refs/bugs/*:refs/bugs/*' \
            '+refs/identities/*:refs/identities/*' || true
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
          # other machines; preStart refetches on the way back up.
          Restart = "always";
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
          git push -q ${origin} \
            'refs/bugs/*:refs/bugs/*' \
            'refs/identities/*:refs/identities/*' || true
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
        locations."/" = {
          proxyPass = "http://unix:/run/anubis/anubis-bugs/anubis.sock";
          proxyWebsockets = true;
        };
      };
    };
}
