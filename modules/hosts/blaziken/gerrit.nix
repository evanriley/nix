{ config, lib, ... }:
let
  inherit (config.meta) secrets;
in
let
  domain = "maybemaybe.lol";
in
{
  flake.modules.nixos.blaziken =
    {
      config,
      pkgs,
      ...
    }:
    {
      # The upstream module runs Gerrit under a dynamic user; cgit needs to
      # read the bare repositories, so run it as a static user instead.
      users.users.gerrit = {
        isSystemUser = true;
        group = "gerrit";
        home = "/var/lib/gerrit";
      };
      users.groups.gerrit = { };

      systemd.services.gerrit.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "gerrit";
        Group = "gerrit";
      };

      systemd.services.gerrit.preStart = ''
        install -Dm600 ${config.age.secrets.mailgun-smtp.path} /var/lib/gerrit/etc/secure.config
      '';
      systemd.services.gerrit.restartTriggers = [
        (builtins.hashFile "sha256" config.age.secrets.mailgun-smtp.file)
      ];

      age.secrets.mailgun-smtp = {
        file = secrets + "/blaziken/mailgun-smtp.age";
        owner = "gerrit";
      };

      services.gerrit = {
        enable = true;
        serverId = "efb806d6-0752-468a-b31d-e463214486d2";
        jvmHeapLimit = "4g";
        listenAddress = "127.0.0.1:8082";
        builtinPlugins = [ "webhooks" ];
        settings = {
          gerrit = {
            canonicalWebUrl = "https://git.${domain}/";
            defaultBranch = "refs/heads/main";
          };
          user.email = "gerrit@news.${domain}";
          auth.type = "HTTP";
          # proxy-https makes Gerrit trust the proxy's REMOTE_USER header.
          httpd.listenUrl = "proxy-https://127.0.0.1:8082";
          sshd = {
            listenAddress = "*:29418";
            advertisedAddress = "git.${domain}:29418";
          };
          sendemail = {
            enable = true;
            smtpServer = "smtp.mailgun.org";
            smtpServerPort = 587;
            smtpEncryption = "tls";
            # SMTP password lives in etc/secure.config, outside the store.
            smtpUser = "postmaster@news.${domain}";
          };
        };
      };

      services.cgit.code = {
        enable = true;
        nginx.virtualHost = "code-upstream";
        # Runs as gerrit so git-http-backend owns the repositories it serves;
        # the module merges its user definition with ours.
        user = "gerrit";
        group = "gerrit";
        scanPath = "/var/lib/gerrit/git";
        gitHttpBackend.checkExportOkFiles = false;
        settings = {
          root-title = "maybemaybe";
          root-desc = "personal monorepo";
          clone-url = [
            "https://code.${domain}/\$GIT_URL"
            "ssh://git.${domain}:29418/\$GIT_URL"
          ];
          enable-git-config = true;
        };
      };

      services.nginx.virtualHosts."code-upstream" = {
        listen = [
          {
            addr = "127.0.0.1";
            port = 8081;
          }
        ];
        # git-http-backend serves every repository under scanPath, including
        # Gerrit's account and access-control data; cgit.ignore does not apply.
        locations."~ ^/All-(Users|Projects)(\\.git)?(/|$)" = {
          priority = 100;
          return = "404";
        };
      };

      services.anubis.instances.code = {
        group = "nginx";
        settings.TARGET = "http://127.0.0.1:8081";
        policy.extraBots = [
          {
            name = "git";
            user_agent_regex = "^git/";
            action = "ALLOW";
          }
          {
            name = "libgit2";
            user_agent_regex = "^libgit2";
            action = "ALLOW";
          }
        ];
      };

      # All-Projects and All-Users are Gerrit bookkeeping, not projects;
      # cgit ignores them via per-repo git config.
      systemd.services.cgit-hide-gerrit-meta = {
        description = "Hide Gerrit meta repositories from cgit";
        after = [ "gerrit.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.git ];
        serviceConfig = {
          User = "gerrit";
          Group = "gerrit";
          Type = "oneshot";
        };
        script = ''
          for repo in All-Projects All-Users; do
            git -C /var/lib/gerrit/git/$repo.git config cgit.ignore 1
          done
        '';
      };

      services.nginx = {
        virtualHosts."git.${domain}" = {
          forceSSL = true;
          useACMEHost = domain;
          basicAuthFile = config.age.secrets.gerrit-htpasswd.path;
          locations."/" = {
            proxyPass = "http://127.0.0.1:8082";
            # Gerrit trusts the basic-auth user from this header.
            extraConfig = ''
              proxy_set_header REMOTE_USER $remote_user;
            '';
          };
        };

        virtualHosts."code.${domain}" = {
          forceSSL = true;
          useACMEHost = domain;
          locations."= /".return = "302 /maybe.git/";
          locations."/" = {
            proxyPass = "http://unix:/run/anubis/anubis-code/anubis.sock";
          };
        };

        virtualHosts."cl.${domain}" = {
          forceSSL = true;
          useACMEHost = domain;
          locations."= /".return = "302 https://git.${domain}/q/status:open";
          locations."~ ^/([0-9]+(/[0-9]+)?)/?$".return = "302 https://git.${domain}/c/maybe/+/$1";
          locations."/".return = "404";
        };
      };

      age.secrets.gerrit-htpasswd = {
        file = secrets + "/blaziken/gerrit-htpasswd.age";
        owner = "nginx";
        group = "nginx";
        mode = "440";
      };
    };
}
