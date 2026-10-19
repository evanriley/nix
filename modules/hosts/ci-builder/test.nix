{ config, inputs, ... }:
let
  nixos = config.flake.modules.nixos;
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
          probeAddress = "192.0.2.1";
          metadataRoot = pkgs.runCommand "metadata-root" { } ''
            mkdir -p $out/computeMetadata/v1/instance/attributes
            echo -n ${instanceName} >$out/computeMetadata/v1/instance/name
            cat >$out/computeMetadata/v1/instance/attributes/startup-script <<'EOF'
            echo ran >/run/ci-builder/startup-script-ran
            EOF
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
            services.nginx = {
              enable = true;
              virtualHosts.metadata = {
                default = true;
                root = metadataRoot;
                extraConfig = "default_type text/plain;";
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
          };

          testScript = ''
            metadata_path = "/computeMetadata/v1/instance/name"
            agent = "runuser -u buildkite-agent-ci-builder --"
            nixbld = "setpriv --reuid=nixbld1 --regid=nixbld --clear-groups --"
            curl = "curl --silent --show-error --max-time 10 --header 'Metadata-Flavor: Google'"

            start_all()
            metadata.wait_for_unit("nginx.service")
            metadata.wait_for_unit("dnsmasq.service")
            builder.wait_for_unit("firewall.service")
            builder.wait_for_unit("multi-user.target")

            def fetch_blocked(prefix, url):
                status, output = builder.execute(f"{prefix} {curl} {url}")
                assert status == 7, f"expected curl exit 7 (connection refused), got {status}: {output}"
                print(f"{prefix} {url}: curl exit {status}")

            def resolves(prefix, args):
                address = builder.succeed(f"{prefix} dig +short {args} probe.test").strip()
                assert address == "${probeAddress}", f"expected ${probeAddress}, got {address!r}"

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

            with subtest("startup runner records the instance name and runs startup-script"):
                builder.wait_until_succeeds("test -f /run/ci-builder/startup-script-ran")
                assert builder.succeed("systemctl show -P Result ci-builder-startup.service").strip() == "success"
                assert builder.succeed("cat /run/ci-builder/agent-name") == "${instanceName}"
                builder.succeed("test $(stat -c %a /run/ci-builder) = 700")

            with subtest("agent stays down without a token"):
                builder.fail("systemctl is-active buildkite-agent-ci-builder.service")
                builder.succeed("journalctl -u buildkite-agent-ci-builder.service | grep -q 'ConditionPathExists'")
          '';
        }
      );
    };
}
