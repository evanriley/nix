{ config, lib, ... }:
let
  inherit (config.meta) secrets domain;
  changesQuery = "q/status:open+-is:wip";
  oauthProviderSection = "gerrit-oauth-provider-discovery-oauth";
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

      systemd.services.gerrit = {
        after = [
          "network-online.target"
          "nginx.service"
          "pocket-id.service"
          "postfix.service"
        ];
        wants = [
          "network-online.target"
          "nginx.service"
          "pocket-id.service"
          "postfix.service"
        ];
        preStart = ''
          secure_config=/var/lib/gerrit/etc/secure.config
          oidc_secret="$(< ${config.age.secrets.gerrit-oidc-secret.path})"
          if [[ ! "$oidc_secret" =~ ^[A-Za-z0-9]+$ ]]; then
            echo "${config.age.secrets.gerrit-oidc-secret.path} is not an alphanumeric client secret; expected the secret Pocket ID shows for the Gerrit client. Re-encrypt gerrit-oidc-secret.age with it." >&2
            exit 1
          fi
          umask 077
          printf '[plugin "${oauthProviderSection}"]\n\tclient-secret = %s\n' "$oidc_secret" > "$secure_config.tmp"
          mv "$secure_config.tmp" "$secure_config"
        '';
        restartTriggers = [
          (builtins.hashFile "sha256" config.age.secrets.gerrit-oidc-secret.file)
        ];
      };

      age.secrets.gerrit-oidc-secret = {
        file = secrets + "/blaziken/gerrit-oidc-secret.age";
        owner = "gerrit";
      };

      services.gerrit = {
        enable = true;
        serverId = "efb806d6-0752-468a-b31d-e463214486d2";
        jvmHeapLimit = "4g";
        listenAddress = "127.0.0.1:8082";
        builtinPlugins = [ "webhooks" ];
        plugins = [
          (builtins.path {
            name = "gerrit-oauth-provider.jar";
            path = ./gerrit-oauth-provider.jar;
            recursive = false;
            sha256 = "sha256-R6IahUTXS294nnxXB1WI4gREg5sqUn6sahtKfvaNfZI=";
          })
        ];
        settings = {
          gerrit = {
            canonicalWebUrl = "https://git.${domain}/";
            defaultBranch = "refs/heads/main";
          };
          user.email = "gerrit@${domain}";
          auth = {
            type = "OAUTH";
            gitBasicAuthPolicy = "HTTP";
            logoutUrl = "https://git.${domain}/${changesQuery}";
          };
          plugin.${oauthProviderSection} = {
            root-url = "https://id.${domain}";
            client-id = "d80c9963-1eb8-464a-9f5f-c1afa18c2c91";
          };
          httpd.listenUrl = "proxy-https://127.0.0.1:8082";
          sshd = {
            listenAddress = "*:29418";
            advertisedAddress = "git.${domain}:29418";
          };
          sendemail = {
            enable = true;
            smtpServer = "127.0.0.1";
            smtpServerPort = 25;
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
          root-title = "maybe";
          root-desc = "maybe monorepo";
          readme = ":README.md";
          about-filter = "${config.services.cgit.code.package}/lib/cgit/filters/about-formatting.sh";
          logo = "/maybe-logo.svg";
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
        locations."= /maybe-logo.svg".alias = pkgs.writeText "maybe-logo.svg" ''
          <svg xmlns="http://www.w3.org/2000/svg" width="110" height="44" viewBox="0 0 110 44">
            <text x="55" y="31" text-anchor="middle" font-family="ui-monospace, Menlo, Consolas, monospace" font-size="26" font-weight="bold" fill="#333">maybe</text>
          </svg>
        '';
      };

      services.anubis.instances.git = {
        group = "nginx";
        settings.TARGET = "http://127.0.0.1:8082";
        policy.extraBots = [
          {
            name = "git";
            user_agent_regex = "^git/";
            action = "ALLOW";
          }
          {
            name = "jgit";
            user_agent_regex = "^JGit/";
            action = "ALLOW";
          }
          {
            name = "libgit2";
            user_agent_regex = "^libgit2";
            action = "ALLOW";
          }
        ];
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
      systemd.services.cgit-repo-config = {
        description = "Set cgit options in Gerrit's repositories";
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
          git -C /var/lib/gerrit/git/maybe.git config cgit.name maybe
        '';
      };

      services.nginx = {
        virtualHosts."git.${domain}" = {
          forceSSL = true;
          useACMEHost = domain;
          locations = {
            "= /".return = "302 /${changesQuery}";
            "/".proxyPass = "http://unix:/run/anubis/anubis-git/anubis.sock";
          }
          // lib.genAttrs [ "/login" "/logout" "/oauth" "/a/" ] (_: {
            proxyPass = "http://127.0.0.1:8082";
          });
        };

        virtualHosts."code.${domain}" = {
          forceSSL = true;
          useACMEHost = domain;
          locations."= /".return = "302 /maybe.git/about/";
          locations."/" = {
            proxyPass = "http://unix:/run/anubis/anubis-code/anubis.sock";
          };
        };

        virtualHosts."cl.${domain}" = {
          forceSSL = true;
          useACMEHost = domain;
          locations."= /".return = "302 https://git.${domain}/${changesQuery}";
          locations."~ ^/([0-9]+(/[0-9]+)?)/?$".return = "302 https://git.${domain}/c/maybe/+/$1";
          locations."/".return = "404";
        };
      };
    };
}
