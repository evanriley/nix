{ config, inputs, ... }:
let
  nixos = config.flake.modules.nixos;
  inherit (config.meta) ciBuilderStartupScript;
in
{
  perSystem =
    { pkgs, system, ... }:
    inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
      checks.ci-builder-metadata = pkgs.testers.runNixOSTest (
        let
          metadataIPv4 = "169.254.169.254";
          metadataIPv6 = "fd20:ce::254";
          instanceName = "ci-builder-test";
          agentToken = "dummy-agent-token";
          probeAddress = "192.0.2.1";
          metadataState = "/srv/metadata";
          metadataRoot = pkgs.runCommand "metadata-root" { } ''
            mkdir -p $out/computeMetadata/v1/instance/attributes
            echo -n ${instanceName} >$out/computeMetadata/v1/instance/name
            cp ${ciBuilderStartupScript} $out/computeMetadata/v1/instance/attributes/startup-script
            echo -n ${agentToken} >$out/computeMetadata/v1/instance/attributes/buildkite-agent-token
          '';
          systemWithoutSwitch = pkgs.runCommand "nixos-system-without-switch" { } "mkdir -p $out/bin";
          cacheDir = "/var/cache/ci-cache";
          cacheSigningKey = pkgs.runCommand "test-cache-signing-key" { nativeBuildInputs = [ pkgs.nix ]; } ''
            nix --extra-experimental-features nix-command key generate-secret --key-name test-cache-1 >$out
          '';
          cacheProbe =
            name: features:
            pkgs.writeText "${name}.nix" ''
              derivation {
                name = "${name}";
                system = "${system}";
                builder = "''${builtins.storePath "${pkgs.bash}"}/bin/bash";
                args = [ "-c" "echo ${name} $builder >$out" ];
                requiredSystemFeatures = [ ${features} ];
              }
            '';
          observeAgentStart = pkgs.writeShellScript "observe-agent-start" ''
            state=idle
            if ! ${pkgs.util-linux}/bin/flock --nonblock /run/nixos/switch-to-configuration.lock true; then
              state=switching
            fi
            ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 10 \
              --header 'Metadata-Flavor: Google' --request PUT --data "$state" \
              http://${metadataIPv4}/computeMetadata/v1/instance/guest-attributes/test/agent-start
          '';
          observeStartupEnd = pkgs.writeShellScript "observe-startup-end" ''
            token=absent
            if [ -e /run/ci-builder/agent-token ] || [ -e /run/ci-builder/agent-token.fetched ]; then
              token=present
            fi
            echo "startup ended with $SERVICE_RESULT: agent token $token, agent $(${pkgs.systemd}/bin/systemctl is-active buildkite-agent-ci-builder.service)"
          '';
          fixedOutputProbe = pkgs.writeText "fixed-output-probe.nix" ''
            derivation {
              name = "fixed-output-probe";
              system = "${system}";
              builder = "''${builtins.storePath "${pkgs.bash}"}/bin/bash";
              PATH = "''${builtins.storePath "${pkgs.curl}"}/bin:''${builtins.storePath "${pkgs.dnsutils}"}/bin:''${builtins.storePath "${pkgs.coreutils}"}/bin";
              args = [
                "-c"
                '''
                  curl --silent --max-time 10 http://${metadataIPv4}/computeMetadata/v1/instance/name
                  status=$?
                  echo "fixed-output resolver: $(</etc/resolv.conf)" >&2
                  echo "fixed-output curl exit $status" >&2
                  [ "$status" = 7 ] || exit 1
                  [ "$(dig +short probe.test)" = ${probeAddress} ] || exit 2
                  echo blocked >$out
                '''
              ];
              outputHashMode = "flat";
              outputHashAlgo = "sha256";
              outputHash = builtins.hashString "sha256" "blocked\n";
            }
          '';
        in
        {
          name = "ci-builder-metadata";
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
                  "= /computeMetadata/v1/instance/attributes/ci-cache-credentials".alias =
                    "${metadataState}/ci-cache-credentials";
                  "= /computeMetadata/v1/instance/attributes/ci-cache-signing-key".alias =
                    "${metadataState}/ci-cache-signing-key";
                  "/computeMetadata/v1/instance/guest-attributes/" = {
                    alias = "${metadataState}/guest-attributes/";
                    extraConfig = ''
                      dav_methods PUT;
                      create_full_put_path on;
                    '';
                  };
                  "= /computeMetadata/v1/instance/guest-attributes/ci-builder/ready" = {
                    alias = "${metadataState}/guest-attributes/ci-builder/ready";
                    extraConfig = ''
                      if (-f ${metadataState}/refuse-ready) {
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
            imports = [ nixos.ci-builder-agent ];
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
            ciBuilder.cacheStore = "file://${cacheDir}?compression=zstd";
            virtualisation.additionalPaths = [ systemWithoutSwitch ];
            systemd.services.register-nix-paths.environment.NIX_REMOTE = "local";
            systemd.services.buildkite-agent-ci-builder.serviceConfig.ExecStartPost = "+${observeAgentStart}";
            systemd.services.ci-builder-startup.serviceConfig.ExecStopPost = "${observeStartupEnd}";
            systemd.services.ci-builder-startup.serviceConfig.ExecStartPre =
              "${pkgs.systemd}/bin/hostnamectl hostname";
            systemd.services.hostnamed-probe = {
              wantedBy = [ "multi-user.target" ];
              stopIfChanged = false;
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${pkgs.systemd}/bin/hostnamectl hostname";
              };
            };
            specialisation.published.configuration = {
              systemd.services.systemd-hostnamed.environment.CI_BUILDER_TEST = "published";
              systemd.services.hostnamed-probe.environment.CI_BUILDER_TEST = "published";
              systemd.services.ci-builder-startup.environment.CI_BUILDER_SYSTEM = "published";
              services.buildkite-agents.ci-builder.tags.system = "published";
            };
          };

          testScript =
            { nodes, ... }:
            ''
              import base64
              import datetime
              import json
              import os
              import re
              import shlex

              base_system = "${nodes.builder.system.build.toplevel}"
              published_system = "${nodes.builder.specialisation.published.configuration.system.build.toplevel}"
              system_without_switch = "${systemWithoutSwitch}"
              metadata_path = "/computeMetadata/v1/instance/name"
              agent = "runuser -u buildkite-agent-ci-builder --"
              nixbld = "setpriv --reuid=nixbld1 --regid=nixbld --clear-groups --"
              curl = "curl --silent --show-error --max-time 10 --header 'Metadata-Flavor: Google'"
              startup_unit = "ci-builder-startup.service"
              agent_unit = "buildkite-agent-ci-builder.service"
              metadata_log = "/var/log/nginx/metadata.log"
              guest_attributes = "${metadataState}/guest-attributes"
              ready = f"{guest_attributes}/ci-builder/ready"
              agent_start = f"{guest_attributes}/test/agent-start"
              system_request = "GET /computeMetadata/v1/instance/attributes/ci-builder-system 200"
              token_request = "GET /computeMetadata/v1/instance/attributes/buildkite-agent-token 200"
              agent_start_request = "PUT /computeMetadata/v1/instance/guest-attributes/test/agent-start "
              ready_request = "PUT /computeMetadata/v1/instance/guest-attributes/ci-builder/ready "
              startup_failure_action_none = base64.b64encode(b"[Unit]\nFailureAction=none\n").decode()
              keep_running_on_startup_failure = f"systemd.set_credential_binary=systemd.unit-dropin.{startup_unit}:{startup_failure_action_none}"
              unit_output_only_on_console = "systemd.journald.forward_to_console=0"

              def start_builder(kernel_params):
                  os.environ["QEMU_KERNEL_PARAMS"] = " ".join(kernel_params)
                  builder.start()
                  del os.environ["QEMU_KERNEL_PARAMS"]

              def serve_system(value):
                  metadata.succeed(f"printf %s {shlex.quote(value)} >${metadataState}/ci-builder-system")

              def requests():
                  return metadata.succeed(f"cat {metadata_log}").splitlines()

              def unit_property(unit, name):
                  return builder.succeed(f"systemctl show -P {name} {unit}").strip()

              def fetch_blocked(prefix, url):
                  status, output = builder.execute(f"{prefix} {curl} {url}")
                  assert status == 7, f"expected curl exit 7 (connection refused), got {status}: {output}"
                  print(f"{prefix} {url}: curl exit {status}")

              def resolves(prefix, args):
                  address = builder.succeed(f"{prefix} dig +short {args} probe.test").strip()
                  assert address == "${probeAddress}", f"expected ${probeAddress}, got {address!r}"

              def reject_system(value, reason, token_requested):
                  serve_system(value)
                  metadata.succeed(f": >{metadata_log}")
                  builder.succeed(f"systemctl reset-failed {startup_unit}")
                  builder.fail(f"systemctl start {startup_unit}")
                  assert_rejected(value, reason, token_requested)

              def assert_rejected(value, reason, token_requested):
                  assert unit_property(startup_unit, "Result") == "exit-code"
                  builder.succeed(f"journalctl -u {startup_unit} -I -o cat | grep -F {shlex.quote(reason)}")
                  builder.fail("test -e /nix/var/nix/profiles/system")
                  assert builder.succeed("readlink -f /run/current-system").strip() == base_system
                  builder.fail("test -e /run/ci-builder/agent-token -o -e /run/ci-builder/agent-token.fetched")
                  assert unit_property(agent_unit, "ActiveEnterTimestampMonotonic") == "0"
                  log = requests()
                  assert system_request in log, log
                  assert any("buildkite-agent-token" in line for line in log) == token_requested, log
                  assert not any(line.startswith("PUT ") for line in log), log
                  metadata.fail(f"test -e {ready}")
                  token = "fetched and removed" if token_requested else "not fetched"
                  print(f"rejected ci-builder-system {value!r} ({reason}): token {token}; no profile, no switch, no agent, no ready")

              def boot_until_ready():
                  metadata.succeed(f"rm -f {ready}", f": >{metadata_log}")
                  builder.start()
                  metadata.wait_until_succeeds(f"test -f {ready}")
                  builder.wait_until_succeeds(f"systemctl show -P ActiveState {startup_unit} | grep -qx inactive")

              def assert_unit_end_powers_off(unit, result):
                  if result == "success":
                      ending = [f"{unit}: Deactivated successfully."]
                  else:
                      ending = [f"{unit}: Failed with result '{result}'.", f"Powering off: unit {unit} failed"]
                  for line in ending:
                      builder.wait_for_console_text(re.escape(line), timeout=datetime.timedelta(minutes=1))
                  builder.wait_for_shutdown(timeout=datetime.timedelta(minutes=2))
                  console = builder.get_console_log()
                  assert re.search(r"(?i)poweroff requested from", console) is None, "a client requested the poweroff"
                  assert (f"Powering off: unit {unit} failed" in console) == (result != "success")
                  print(f"{unit} ended with result {result!r} and systemd powered the VM off")

              metadata.start()
              metadata.wait_for_unit("nginx.service")
              metadata.wait_for_unit("dnsmasq.service")
              serve_system(f"{published_system}/bin/switch-to-configuration")
              start_builder([keep_running_on_startup_failure])
              builder.wait_for_unit("firewall.service")
              builder.wait_for_unit("multi-user.target")

              with subtest("root fetches metadata over IPv4 and IPv6"):
                  for url in ["http://${metadataIPv4}", "http://[${metadataIPv6}]"]:
                      assert builder.wait_until_succeeds(f"{curl} {url}{metadata_path}") == "${instanceName}"

              with subtest("agent user cannot fetch metadata"):
                  fetch_blocked(agent, f"http://${metadataIPv4}{metadata_path}")
                  fetch_blocked(agent, f"http://[${metadataIPv6}]{metadata_path}")

              with subtest("nixbld group cannot fetch metadata"):
                  fetch_blocked(nixbld, f"http://${metadataIPv4}{metadata_path}")
                  fetch_blocked(nixbld, f"http://[${metadataIPv6}]{metadata_path}")

              with subtest("agent user and nixbld group resolve names over UDP and TCP"):
                  for prefix in [agent, nixbld]:
                      resolves(prefix, "")
                      resolves(prefix, "+tcp")
                      resolves(prefix, "@${metadataIPv6}")

              with subtest("fixed-output derivation cannot fetch metadata but resolves names"):
                  builder.succeed("test -e /dev/net/tun")
                  builder.succeed("nix-build --no-out-link --option substitute false ${fixedOutputProbe} >&2")

              with subtest("startup runner records the instance name and runs the published startup-script"):
                  builder.wait_until_succeeds(f"systemctl is-failed --quiet {startup_unit}")
                  builder.succeed("cmp /run/ci-builder/startup-script ${ciBuilderStartupScript}")
                  assert builder.succeed("cat /run/ci-builder/agent-name") == "${instanceName}"
                  builder.succeed("test $(stat -c %a /run/ci-builder) = 700")

              with subtest("malformed ci-builder-system fails closed before the profile is set"):
                  malformed = "expected one /nix/store/<hash>-nixos-system-* path"
                  assert_rejected(f"{published_system}/bin/switch-to-configuration", malformed, token_requested=False)
                  for value in [
                      "",
                      f"{published_system} {published_system}",
                      f"{published_system}\n{published_system}",
                      "/nix/store/" + "a" * 32 + "-hello-2.12.1",
                  ]:
                      reject_system(value, malformed, token_requested=False)
                  reject_system("${systemWithoutSwitch}", "has no executable bin/switch-to-configuration", token_requested=True)

              with subtest("unset cache metadata leaves the VM without cache files"):
                  log = requests()
                  for key in ["ci-cache-credentials", "ci-cache-signing-key"]:
                      assert f"GET /computeMetadata/v1/instance/attributes/{key} 404" in log, log
                  builder.fail("test -e /run/ci-builder/cache-credentials -o -e /run/ci-builder/cache-signing-key")

              with subtest("agent stays down without a token"):
                  builder.fail(f"systemctl is-active {agent_unit}")
                  builder.succeed(f"journalctl -u {agent_unit} | grep -q 'ConditionPathExists'")

              builder.shutdown()

              with subtest("a failed startup fails closed and powers the VM off"):
                  serve_system(system_without_switch)
                  metadata.succeed(f": >{metadata_log}")
                  builder.start()
                  assert_unit_end_powers_off(startup_unit, "exit-code")
                  console = builder.get_console_log()
                  ended = "startup ended with exit-code: agent token absent, agent inactive"
                  assert ended in console, "expected no token and no agent when the startup unit ended"
                  assert console.index(ended) < console.index(f"Powering off: unit {startup_unit} failed"), "expected the startup unit to fail closed before the poweroff"
                  log = requests()
                  assert token_request in log, log
                  assert not any(line.startswith("PUT ") for line in log), log
                  metadata.fail(f"test -e {ready}")

              with subtest("a failed startup prints its output on the serial console without the token"):
                  metadata.succeed(f": >{metadata_log}")
                  start_builder([unit_output_only_on_console])
                  rejected = f"{system_without_switch} has no executable bin/switch-to-configuration"
                  builder.wait_for_console_text(rf"ci-builder-startup\[\d+\]: {re.escape(rejected)}", timeout=datetime.timedelta(minutes=1))
                  builder.wait_for_shutdown(timeout=datetime.timedelta(minutes=2))
                  console = builder.get_console_log()
                  realised = rf"ci-builder-startup\[\d+\]: {re.escape(system_without_switch)}$"
                  assert re.search(realised, console, re.MULTILINE), "expected the stdout of nix-store --realise on the console"
                  assert token_request in requests()
                  assert "${agentToken}" not in console, "expected the token to be absent from the serial console"
                  metadata.fail(f"test -e {ready}")

              serve_system(published_system)
              metadata.succeed(
                  "printf %s dummy-credentials >${metadataState}/ci-cache-credentials",
                  "cp ${cacheSigningKey} ${metadataState}/ci-cache-signing-key",
                  "chmod 644 ${metadataState}/ci-cache-*",
              )
              boot_until_ready()

              with subtest("cache secrets are root-only"):
                  for name in ["cache-credentials", "cache-signing-key"]:
                      assert builder.succeed(f"stat -c '%a %U %G' /run/ci-builder/{name}").strip() == "400 root root"
                      builder.fail(f"{agent} cat /run/ci-builder/{name}")
                  builder.succeed("cmp /run/ci-builder/cache-signing-key ${cacheSigningKey}")

              with subtest("only big-parallel outputs are uploaded, signed, with their closure"):
                  heavy = builder.succeed(f"{agent} nix-build --no-out-link --option substitute false ${cacheProbe "heavy-probe" ''"big-parallel"''}").strip()
                  light = builder.succeed(f"{agent} nix-build --no-out-link --option substitute false ${cacheProbe "light-probe" ""}").strip()
                  def narinfo(path):
                      return "${cacheDir}/" + os.path.basename(path).split("-", 1)[0] + ".narinfo"
                  info = builder.succeed(f"cat {narinfo(heavy)}")
                  assert re.search(r"^Sig: test-cache-1:", info, re.MULTILINE), info
                  builder.succeed(f"test -e {narinfo('${pkgs.bash}')}")
                  builder.fail(f"test -e {narinfo(light)}")

              with subtest("token is root-only and never logged"):
                  assert builder.succeed("stat -c '%a %U %G' /run/ci-builder/agent-token").strip() == "400 root root"
                  assert builder.succeed("cat /run/ci-builder/agent-token") == "${agentToken}"
                  builder.fail("test -e /run/ci-builder/agent-token.fetched")
                  builder.fail(f"{agent} cat /run/ci-builder/agent-token")
                  status, _ = builder.execute("journalctl -b -o export | grep -qaFf /run/ci-builder/agent-token")
                  assert status == 1, f"expected the token to be absent from the journal, grep exit {status}"
                  assert "${agentToken}" not in builder.get_console_log(), "expected the token to be absent from the serial console"

              with subtest("profile and current system are the served ci-builder-system"):
                  assert builder.succeed("readlink -f /nix/var/nix/profiles/system").strip() == published_system
                  assert builder.succeed("readlink -f /run/current-system").strip() == published_system

              with subtest("agent starts once, after the switch, from the published configuration"):
                  builder.succeed(f"systemctl is-active {agent_unit}")
                  assert metadata.succeed(f"cat {agent_start}") == "idle"
                  log = requests()
                  assert len([line for line in log if line.startswith(agent_start_request)]) == 1, log
                  config = builder.succeed("cat /var/lib/buildkite-agent-ci-builder/buildkite-agent.cfg").splitlines()
                  for line in [
                      'token="${agentToken}"',
                      'name="${instanceName}"',
                      'tags="queue=spot-builders,system=published"',
                  ]:
                      assert line in config, f"expected {line} in the agent config"
                  switch_output = builder.succeed(f"journalctl -b -u {startup_unit} -o cat").splitlines()
                  started = [line for line in switch_output if line.startswith("the following new units were started: ")]
                  assert not any(agent_unit in line for line in started), started

              with subtest("ready is set only after the agent is active"):
                  log = requests()
                  print("\n".join(log))
                  started_at = next(i for i, line in enumerate(log) if line.startswith(agent_start_request))
                  ready_at = log.index(ready_request + "201")
                  assert log.index(system_request) < log.index(token_request) < started_at < ready_at, log
                  assert metadata.succeed(f"cat {ready}") == "1"

              with subtest("startup runner succeeds once without a restart by the switch"):
                  assert unit_property(startup_unit, "Result") == "success"
                  invocations = set()
                  for line in builder.succeed(f"journalctl -b -u {startup_unit} -o json").splitlines():
                      entry = json.loads(line)
                      for field in ["_SYSTEMD_INVOCATION_ID", "INVOCATION_ID"]:
                          if field in entry:
                              invocations.add(entry[field])
                  assert invocations == {unit_property(startup_unit, "InvocationID")}, invocations
                  skipped = [line for line in switch_output if line.startswith("NOT restarting the following changed units: ")]
                  assert any(startup_unit in line.split(": ", 1)[1].split(", ") for line in skipped), switch_output

              with subtest("the switch leaves a running hostnamed alone while a restarted unit starts it again"):
                  switch_line = lambda prefix: next((line.removeprefix(prefix).split(", ") for line in switch_output if line.startswith(prefix)), [])
                  assert "hostnamed-probe.service" in switch_line("restarting the following units: "), switch_output
                  assert "systemd-hostnamed.service" in switch_line("NOT restarting the following changed units: "), switch_output
                  assert not any("systemd-hostnamed" in line for line in switch_output if line.startswith("stopping the following units: ")), switch_output
                  assert unit_property("systemd-hostnamed.socket", "ActiveState") == "active"

              with subtest("killing the whole agent unit powers the VM off"):
                  builder.execute(f"systemctl kill --signal=SIGKILL {agent_unit} >&2 &", check_return=False)
                  assert_unit_end_powers_off(agent_unit, "signal")

              with subtest("a failed ready update stops the agent and powers the VM off"):
                  metadata.succeed("touch ${metadataState}/refuse-ready", f"rm {ready}", f": >{metadata_log}")
                  builder.start()
                  refused = ready_request + "403"
                  metadata.wait_until_succeeds(f"grep -qxF '{refused}' {metadata_log}")
                  assert_unit_end_powers_off(agent_unit, "success")
                  log = requests()
                  started_at = next(i for i, line in enumerate(log) if line.startswith(agent_start_request))
                  assert started_at < log.index(refused), log
                  assert metadata.succeed(f"cat {agent_start}") == "idle"
                  metadata.fail(f"test -e {ready}")
                  metadata.succeed("rm ${metadataState}/refuse-ready")

              with subtest("a clean agent exit powers the VM off"):
                  boot_until_ready()
                  builder.execute(f"systemctl kill --kill-whom=main --signal=SIGTERM {agent_unit} >&2 &", check_return=False)
                  assert_unit_end_powers_off(agent_unit, "success")

              with subtest("a non-zero agent exit powers the VM off"):
                  boot_until_ready()
                  builder.execute(f"systemctl kill --kill-whom=main --signal=SIGQUIT {agent_unit} >&2 &", check_return=False)
                  assert_unit_end_powers_off(agent_unit, "exit-code")

              with subtest("a system shutdown sends the agent SIGQUIT to cancel its job"):
                  boot_until_ready()
                  builder.execute("systemctl poweroff >&2 &", check_return=False)
                  builder.wait_for_console_text(r"buildkite-agent\[\d+\]: SIGQUIT: quit", timeout=datetime.timedelta(minutes=1))
                  builder.wait_for_shutdown(timeout=datetime.timedelta(minutes=2))
            '';
        }
      );
    };
}
