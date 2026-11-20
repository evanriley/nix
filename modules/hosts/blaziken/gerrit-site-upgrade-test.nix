{ config, inputs, ... }:
let
  nixos = config.flake.modules.nixos;
  oauthProviderSection = "gerrit-oauth-provider-discovery-oauth";
in
{
  perSystem =
    { pkgs, system, ... }:
    inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
      checks.gerrit-site-upgrade = pkgs.testers.runNixOSTest (
        let
          gerritBefore = pkgs.gerrit.overrideAttrs {
            version = "3.14.5";
            src = pkgs.fetchurl {
              url = "https://gerrit-releases.storage.googleapis.com/gerrit-3.14.5.war";
              hash = "sha256-MR+iSyEmpsPvDfZmnKy6niOxW4g0aOrCQuiXLSPugxY=";
            };
          };
          gerritAfter = pkgs.gerrit;
          oauth = builtins.path {
            name = "gerrit-oauth-provider.jar";
            path = ./gerrit-oauth-provider.jar;
            recursive = false;
            sha256 = "sha256-j66C6GCLFeUGzC0rjO4aZ54/M7O5BJYJcZd+Y8lOdDk=";
          };
          identityProvider = "127.0.0.1:8090";
        in
        {
          name = "gerrit-site-upgrade";
          nodes.machine =
            { lib, ... }:
            {
              imports = [ nixos.gerrit-site-upgrade ];
              virtualisation.memorySize = 3072;
              environment.systemPackages = [ pkgs.git ];

              services.gerrit = {
                enable = true;
                package = lib.mkDefault gerritBefore;
                serverId = "9e9c9b9a-0000-4000-8000-000000000000";
                jvmHeapLimit = "1g";
                listenAddress = "127.0.0.1:8082";
                builtinPlugins = [ "webhooks" ];
                settings = {
                  gerrit.canonicalWebUrl = "http://localhost:8082/";
                  auth = {
                    type = lib.mkDefault "DEVELOPMENT_BECOME_ANY_ACCOUNT";
                    gitBasicAuthPolicy = "HTTP";
                  };
                  plugin.${oauthProviderSection} = {
                    root-url = "http://${identityProvider}";
                    client-id = "test-client";
                  };
                  httpd.listenUrl = "proxy-https://127.0.0.1:8082";
                  sshd.listenAddress = "*:29418";
                };
              };

              systemd.services.gerrit = {
                after = [ "nginx.service" ];
                wants = [ "nginx.service" ];
                preStart = ''
                  umask 077
                  printf '[plugin "${oauthProviderSection}"]\n\tclient-secret = %s\n' test-secret > etc/secure.config
                '';
              };

              services.nginx = {
                enable = true;
                virtualHosts.identity = {
                  listen = [
                    {
                      addr = "127.0.0.1";
                      port = 8090;
                    }
                  ];
                  locations."/".extraConfig = ''
                    default_type application/json;
                    return 200 '${
                      builtins.toJSON {
                        issuer = "http://${identityProvider}";
                        authorization_endpoint = "http://${identityProvider}/authorize";
                        token_endpoint = "http://${identityProvider}/token";
                        userinfo_endpoint = "http://${identityProvider}/userinfo";
                      }
                    }';
                  '';
                };
              };

              specialisation.upgraded.configuration.services.gerrit = {
                package = gerritAfter;
                plugins = [ oauth ];
                settings.auth.type = "OAUTH";
              };
            };

          testScript =
            { nodes, ... }:
            let
              system = nodes.machine.system.build.toplevel;
            in
            ''
              import json

              site = "/var/lib/gerrit"

              def start_gerrit():
                  machine.succeed("systemctl start gerrit.service")
                  machine.wait_until_succeeds("curl -sf http://127.0.0.1:8082/config/server/version")
                  machine.wait_for_open_port(29418)

              def gerrit_version():
                  body = machine.succeed("curl -sf http://127.0.0.1:8082/config/server/version")
                  return json.loads(body.removeprefix(")]}'"))

              def start_log():
                  invocation = machine.succeed("systemctl show --property=InvocationID --value gerrit.service").strip()
                  return machine.succeed(f"journalctl --no-pager _SYSTEMD_INVOCATION_ID={invocation}")

              def assert_site_linked(package):
                  assert machine.succeed(f"cat {site}/.nixos-gerrit-package").strip() == package
                  machine.succeed(f"readlink {site}/etc/gerrit.config | grep -q '^/nix/store/.*-gerrit.conf$'")
                  machine.succeed(f"readlink {site}/etc/replication.config | grep -q '^/nix/store/.*-replication.conf$'")

              machine.wait_for_unit("multi-user.target")

              with subtest("a fresh site is initialised and records its package"):
                  start_gerrit()
                  assert gerrit_version() == "${gerritBefore.version}"
                  assert_site_linked("${gerritBefore}")

              with subtest("a package change upgrades the site before Gerrit starts"):
                  machine.succeed("${system}/specialisation/upgraded/bin/switch-to-configuration test")
                  start_gerrit()
                  machine.succeed("systemctl is-active gerrit.service")
                  assert gerrit_version() == "${gerritAfter.version}"
                  log = start_log()
                  assert "Migrating data to schema 187" in log, log
                  assert "Loaded plugin gerrit-oauth-provider" in log, log
                  assert_site_linked("${gerritAfter}")
                  machine.succeed(f"git -c safe.directory='*' -C {site}/git/All-Projects.git show refs/meta/config:project.config | grep -q aiReview")
                  unreadable = machine.succeed(f"find -L {site}/git -type f ! -perm -g+r")
                  assert unreadable == "", unreadable

              with subtest("a restart with the same package skips init"):
                  machine.succeed("systemctl restart gerrit.service")
                  start_gerrit()
                  log = start_log()
                  assert "'plugins' -> " in log, log
                  assert "Initialized " not in log, log
                  assert gerrit_version() == "${gerritAfter.version}"
            '';
        }
      );
    };
}
