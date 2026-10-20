{ config, ... }:
let
  nixos = config.flake.modules.nixos;
  inherit (config.meta) ciRemoteBuilderStartupScript;
in
{
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.ci-remote-builder = pkgs.testers.runNixOSTest (
        let
          metadataIPv4 = "169.254.169.254";
          metadataIPv6 = "fd20:ce::254";
          probeAddress = "192.0.2.1";
          metadataState = "/srv/metadata";
          remoteBuildOutput = "built-by-the-remote-builder";
          metadataRoot = pkgs.runCommand "metadata-root" { } ''
            mkdir -p $out/computeMetadata/v1/instance/attributes
            echo -n ci-remote-builder-test >$out/computeMetadata/v1/instance/name
            cp ${ciRemoteBuilderStartupScript} $out/computeMetadata/v1/instance/attributes/startup-script
          '';
          sshKeys = import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs;
          production = config.flake.nixosConfigurations.ci-remote-builder.config;
          expectedAuthorizedKeys = map (builtins.replaceStrings
            [ production.ciBuilder.remoteBuilderAuthorizedKey ]
            [ sshKeys.snakeOilEd25519PublicKey ]
          ) production.users.users.builder.openssh.authorizedKeys.keys;
          remoteBuildProbe = pkgs.writeText "remote-build-probe.nix" ''
            derivation {
              name = "remote-build-probe";
              system = "${system}";
              builder = "''${builtins.storePath "${pkgs.bash}"}/bin/bash";
              args = [
                "-c"
                "''${builtins.storePath "${pkgs.hello}"}/bin/hello --greeting=${remoteBuildOutput} >$out"
              ];
              requiredSystemFeatures = [ "big-parallel" ];
            }
          '';
          builderTestConfig = {
            networking.interfaces.eth1 = {
              ipv4.addresses = [
                {
                  address = "169.254.0.2";
                  prefixLength = 16;
                }
              ];
              ipv6.addresses = [
                {
                  address = "fd20:ce::2";
                  prefixLength = 64;
                }
              ];
            };
            networking.nameservers = [ metadataIPv4 ];
            environment.systemPackages = [
              pkgs.curl
              pkgs.dnsutils
            ];
            boot.loader.grub.enable = false;
            systemd.services.register-nix-paths.environment.NIX_REMOTE = "local";
          };
        in
        {
          name = "ci-remote-builder";
          node.pkgsReadOnly = false;

          nodes.metadata = {
            networking.interfaces.eth1 = {
              ipv4.addresses = [
                {
                  address = metadataIPv4;
                  prefixLength = 16;
                }
              ];
              ipv6.addresses = [
                {
                  address = metadataIPv6;
                  prefixLength = 64;
                }
              ];
            };
            networking.firewall.allowedTCPPorts = [
              53
              80
            ];
            networking.firewall.allowedUDPPorts = [ 53 ];
            services.dnsmasq = {
              enable = true;
              resolveLocalQueries = false;
              settings = {
                no-resolv = true;
                bind-dynamic = true;
                listen-address = [
                  metadataIPv4
                  metadataIPv6
                ];
                address = "/probe.test/${probeAddress}";
              };
            };
            systemd.tmpfiles.rules = [
              "d ${metadataState} 0755 root root -"
              "d ${metadataState}/guest-attributes 0750 nginx nginx -"
            ];
            systemd.services.nginx.serviceConfig.ReadWritePaths = [ "${metadataState}/guest-attributes" ];
            services.nginx = {
              enable = true;
              commonHttpConfig = "log_format metadata '$request_method $uri $status';";
              virtualHosts.metadata = {
                default = true;
                root = metadataRoot;
                extraConfig = ''
                  default_type text/plain;
                  access_log /var/log/nginx/metadata.log metadata;
                '';
                locations = {
                  "= /computeMetadata/v1/instance/attributes/ci-builder-system".alias =
                    "${metadataState}/ci-builder-system";
                  "/computeMetadata/v1/instance/guest-attributes/" = {
                    alias = "${metadataState}/guest-attributes/";
                    extraConfig = ''
                      dav_methods PUT;
                      create_full_put_path on;
                    '';
                  };
                  "= /computeMetadata/v1/instance/guest-attributes/ci-remote-builder/host-key" = {
                    alias = "${metadataState}/guest-attributes/ci-remote-builder/host-key";
                    extraConfig = ''
                      if (-f ${metadataState}/refuse-host-key) {
                        return 403;
                      }
                      dav_methods PUT;
                      create_full_put_path on;
                    '';
                  };
                };
              };
            };
          };

          nodes.builder = {
            imports = [
              nixos.ci-builder-agent
              builderTestConfig
            ];
            specialisation.remote = {
              inheritParentConfig = false;
              configuration = {
                imports = [
                  nixos.ci-remote-builder
                  builderTestConfig
                ];
                ciBuilder.remoteBuilderAuthorizedKey = sshKeys.snakeOilEd25519PublicKey;
              };
            };
          };

          nodes.client = {
            imports = [ nixos.nix-core ];
            nix.settings.max-jobs = 0;
            virtualisation.additionalPaths = [ pkgs.hello ];
          };

          testScript =
            { nodes, ... }:
            ''
              import base64
              import datetime
              import json
              import shlex
              import urllib.parse

              remote_system = "${nodes.builder.specialisation.remote.configuration.system.build.toplevel}"
              startup_unit = "ci-builder-startup.service"
              sshd_unit = "sshd.service"
              metadata_log = "/var/log/nginx/metadata.log"
              guest_attributes = "${metadataState}/guest-attributes/ci-remote-builder"
              host_key_attribute = f"{guest_attributes}/host-key"
              ready = f"{guest_attributes}/ready"
              system_request = "GET /computeMetadata/v1/instance/attributes/ci-builder-system 200"
              host_key_request = "PUT /computeMetadata/v1/instance/guest-attributes/ci-remote-builder/host-key "
              ready_request = "PUT /computeMetadata/v1/instance/guest-attributes/ci-remote-builder/ready "
              setup_failed = "Remote builder setup failed"
              nixbld = "setpriv --reuid=nixbld1 --regid=nixbld --clear-groups --"
              builder_user = "setpriv --reuid=builder --regid=builder --clear-groups --"
              curl = "curl --silent --show-error --max-time 10 --header 'Metadata-Flavor: Google'"
              client_key = "/root/ci-remote-builder-key"
              known_hosts = "/root/ci-remote-builder-known-hosts"
              ssh = f"ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes -o UserKnownHostsFile={known_hosts}"
              count_builder_daemon_connections = "journalctl -b -t nix-daemon -o cat | grep -c 'is user builder (trusted)$'"
              forward_unit = "ci-remote-builder-forward.service"
              forward_port = 2222

              def serve_system(value):
                  metadata.succeed(f"printf %s {shlex.quote(value)} >${metadataState}/ci-builder-system")

              def requests():
                  return metadata.succeed(f"cat {metadata_log}").splitlines()

              def puts():
                  return [line for line in requests() if line.startswith("PUT ")]

              def effective_sshd_config():
                  return builder.succeed("/run/current-system/sw/bin/sshd -T").lower().splitlines()

              def daemon_connections_from_builder():
                  return int(builder.succeed(f"{count_builder_daemon_connections} || true").strip())

              def unit_property(unit, name):
                  return builder.succeed(f"systemctl show -P {name} {unit}").strip()

              def clear_published():
                  metadata.succeed(f"rm -f {host_key_attribute} {ready}", f": >{metadata_log}")

              def fetch_blocked(prefix, url):
                  status, output = builder.execute(f"{prefix} {curl} {url}")
                  assert status == 7, f"expected curl exit 7 (connection refused), got {status}: {output}"
                  print(f"{prefix} {url}: curl exit {status}")

              def resolves(prefix, args):
                  address = builder.succeed(f"{prefix} dig +short {args} probe.test").strip()
                  assert address == "${probeAddress}", f"expected ${probeAddress}, got {address!r}"

              def assert_powered_off_unpublished(reason):
                  builder.wait_for_shutdown(timeout=datetime.timedelta(minutes=2))
                  console = builder.get_console_log()
                  assert setup_failed in console, "expected the startup script to report its failure"
                  assert reason in console, f"expected {reason!r} on the console"
                  metadata.fail(f"test -e {ready}")
                  log = requests()
                  assert system_request in log, log
                  assert not any(line.startswith(ready_request) for line in log), log
                  print(f"{reason}: VM powered off, ready never set")

              metadata.start()
              metadata.wait_for_unit("nginx.service")
              metadata.wait_for_unit("dnsmasq.service")
              client.start()

              with subtest("malformed ci-builder-system powers off before sshd starts or anything is published"):
                  clear_published()
                  serve_system(f"{remote_system}/bin/switch-to-configuration")
                  builder.start()
                  assert_powered_off_unpublished("expected one /nix/store/<hash>-nixos-system-* path")
                  assert puts() == [], puts()
                  metadata.fail(f"test -e {host_key_attribute}")
                  assert "SSH Daemon" not in builder.get_console_log()

              serve_system(remote_system)
              clear_published()
              builder.start()
              metadata.wait_until_succeeds(f"test -f {ready}")
              builder.wait_until_succeeds(f"systemctl show -P ActiveState {startup_unit} | grep -qx inactive")

              with subtest("profile and current system are the served ci-builder-system"):
                  assert builder.succeed("readlink -f /nix/var/nix/profiles/system").strip() == remote_system
                  assert builder.succeed("readlink -f /run/current-system").strip() == remote_system

              with subtest("sshd is active on port 22 and accepts only public keys for builder"):
                  builder.succeed(f"systemctl is-active {sshd_unit}")
                  effective = effective_sshd_config()
                  for line in [
                      "port 22",
                      "passwordauthentication no",
                      "kbdinteractiveauthentication no",
                      "permitrootlogin no",
                      "allowusers builder",
                  ]:
                      assert line in effective, f"expected {line!r} in sshd -T"

              with subtest("published host key is the key sshd serves"):
                  host_key = metadata.succeed(f"cat {host_key_attribute}")
                  assert host_key == builder.succeed("cat /etc/ssh/ssh_host_ed25519_key.pub").rstrip("\n"), host_key
                  key_type, key_data = host_key.split()[:2]
                  scanned = client.succeed("ssh-keyscan -q -T 10 -t ed25519 builder").strip()
                  assert scanned == f"builder {key_type} {key_data}", scanned
                  client.succeed(f"printf 'builder %s %s\\n' {key_type} {key_data} >{known_hosts}")

              with subtest("host key is published after the switch and ready only after it"):
                  log = requests()
                  print("\n".join(log))
                  assert puts() == [host_key_request + "201", ready_request + "201"], puts()
                  assert log.index(system_request) < log.index(host_key_request + "201") < log.index(ready_request + "201"), log
                  assert metadata.succeed(f"cat {ready}") == "1"

              with subtest("remote builder runs no Buildkite agent and fetches no token"):
                  builder.fail("systemctl cat buildkite-agent-ci-builder.service")
                  assert not any("buildkite-agent-token" in line for line in requests())

              with subtest("builder user and nixbld group cannot fetch metadata but resolve names"):
                  builder_uid = builder.succeed("id -u builder").strip()
                  for command in ["iptables", "ip6tables"]:
                      rules = builder.succeed(f"{command} -w -S ci-builder-metadata")
                      assert f"--uid-owner {builder_uid} " in rules, rules
                      assert "--gid-owner" in rules, rules
                  for prefix in [builder_user, nixbld]:
                      fetch_blocked(prefix, "http://${metadataIPv4}/computeMetadata/v1/instance/name")
                      fetch_blocked(prefix, "http://[${metadataIPv6}]/computeMetadata/v1/instance/name")
                      resolves(prefix, "")
                      resolves(prefix, "+tcp")
                      resolves(prefix, "@${metadataIPv6}")

              with subtest("builder's authorized key is the production key line with the test key"):
                  authorized_keys = [line for line in builder.succeed("cat /etc/ssh/authorized_keys.d/builder").splitlines() if line]
                  print("\n".join(authorized_keys))
                  assert authorized_keys == ${builtins.toJSON expectedAuthorizedKeys}, authorized_keys

              client.succeed("install -m 0600 ${sshKeys.snakeOilEd25519PrivateKey} " + client_key)

              with subtest("sshd refuses password logins and root"):
                  status, output = client.execute(
                      f"{ssh} -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive builder@builder true 2>&1"
                  )
                  assert status == 255 and "Permission denied (publickey)." in output, (status, output)
                  status, output = client.execute(f"{ssh} -i {client_key} root@builder true 2>&1")
                  assert status == 255 and "Permission denied (publickey)." in output, (status, output)

              host_key_base64 = base64.b64encode(host_key.encode()).decode()

              with subtest("client reaches the builder's nix-daemon as a trusted user against the published host key"):
                  quoted_host_key = urllib.parse.quote(host_key_base64, safe="")
                  store = f"ssh-ng://builder@builder?ssh-key={client_key}&base64-ssh-public-host-key={quoted_host_key}"
                  output = client.succeed(f"nix store ping --store {shlex.quote(store)} 2>&1")
                  print(output)
                  assert "Trusted: 1" in output, output

              with subtest("ssh as builder runs nix-daemon --stdio instead of the requested command"):
                  connections = daemon_connections_from_builder()
                  status, output = client.execute(f"{ssh} -i {client_key} builder@builder id </dev/null 2>&1")
                  print(f"ssh builder@builder id: exit {status}, output {output!r}")
                  assert "uid=" not in output, output
                  builder.wait_until_succeeds(f"test \"$({count_builder_daemon_connections})\" -gt {connections}")

              with subtest("ssh as builder gets no pty"):
                  assert "permittty yes" in effective_sshd_config()
                  status, output = client.execute(f"{ssh} -tt -i {client_key} builder@builder </dev/null 2>&1")
                  print(f"ssh -tt builder@builder: exit {status}, output {output!r}")
                  assert "PTY allocation request failed on channel 0" in output, (status, output)

              with subtest("ssh as builder cannot forward a local port"):
                  assert "allowtcpforwarding yes" in effective_sshd_config()
                  client.succeed(
                      f"systemd-run --unit={forward_unit} {ssh} -i {client_key} -N "
                      f"-L 127.0.0.1:{forward_port}:127.0.0.1:22 builder@builder"
                  )
                  client.wait_until_succeeds(f"ss -Htln 'sport = :{forward_port}' | grep -q .")
                  status, banner = client.execute(f"timeout 10 bash -c 'exec 3<>/dev/tcp/127.0.0.1/{forward_port} && cat <&3'")
                  print(f"forwarded connection: exit {status}, received {banner!r}")
                  assert "SSH-2.0-" not in banner, banner
                  client.wait_until_succeeds(f"journalctl -u {forward_unit} -o cat | grep -q 'administratively prohibited'")
                  builder.succeed("journalctl -b -t sshd-session -o cat | grep -q 'refused local port forward: originator 127.0.0.1 port [0-9]*, target 127.0.0.1 port 22'")
                  print(client.succeed(f"journalctl -u {forward_unit} -o cat"))
                  client.succeed(f"systemctl stop {forward_unit}")

              with subtest("client copies an unsigned input to the builder and builds a big-parallel derivation there over ssh-ng"):
                  machine = f"ssh-ng://builder@builder ${system} {client_key} 1 1 big-parallel big-parallel {host_key_base64}"
                  builder.fail("nix-store --check-validity ${pkgs.hello}")
                  output = client.succeed(
                      "nix-build --no-out-link --option substitute false "
                      f"--option builders {shlex.quote(machine)} ${remoteBuildProbe}"
                  ).strip()
                  assert client.succeed(f"cat {output}") == "${remoteBuildOutput}\n"
                  assert builder.succeed(f"cat {output}") == "${remoteBuildOutput}\n"
                  builder.succeed("nix-store --check-validity ${pkgs.hello}")
                  print(f"built {output} on the builder and copied it to the client")

              with subtest("startup runner succeeds once without a restart by the switch"):
                  assert unit_property(startup_unit, "Result") == "success"
                  invocations = set()
                  for line in builder.succeed(f"journalctl -b -u {startup_unit} -o json").splitlines():
                      entry = json.loads(line)
                      for field in ["_SYSTEMD_INVOCATION_ID", "INVOCATION_ID"]:
                          if field in entry:
                              invocations.add(entry[field])
                  assert invocations == {unit_property(startup_unit, "InvocationID")}, invocations

              with subtest("a refused host-key update powers the VM off without reporting ready"):
                  builder.shutdown()
                  metadata.succeed("touch ${metadataState}/refuse-host-key")
                  clear_published()
                  builder.start()
                  assert_powered_off_unpublished("Metadata request for instance/guest-attributes/ci-remote-builder/host-key failed")
                  assert puts() == [host_key_request + "403"], puts()
                  metadata.succeed("rm ${metadataState}/refuse-host-key")
            '';
        }
      );
    };
}
