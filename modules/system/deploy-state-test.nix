{ config, inputs, ... }:
let
  nixos = config.flake.modules.nixos;
  inherit (inputs.nixpkgs) lib;
  baselineExempt = {
    "/var/lib/dhcpcd" = "DHCP lease files of the test machine";
    "/var/lib/systemd/linger" = "logind linger marker files";
  };
in
{
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.deploy-state = pkgs.testers.runNixOSTest {
        name = "deploy-state";
        nodes.machine =
          { pkgs, ... }:
          let
            schemaFile = "/var/lib/toy/schema";
            toy = pkgs.writeShellScript "toy" ''
              [ -e ${schemaFile} ] || echo schema=1 > ${schemaFile}
              grep -qx schema=1 ${schemaFile}
              exec ${pkgs.coreutils}/bin/sleep infinity
            '';
            toyV2 = pkgs.writeShellScript "toy-v2" ''
              [ -e ${schemaFile} ] || echo schema=1 > ${schemaFile}
              if grep -qx schema=1 ${schemaFile}; then echo schema=2 > ${schemaFile}; fi
              grep -qx schema=2 ${schemaFile}
              exec ${pkgs.coreutils}/bin/sleep infinity
            '';
          in
          {
            imports = [ nixos.deploy-state ];

            environment.systemPackages = [ pkgs.jq ];

            deployState = {
              enforce = true;
              exempt = baselineExempt;
              entries.toy = {
                key = [ "1" ];
                units = [ "toy.service" ];
                paths = [ "/var/lib/toy" ];
              };
            };

            systemd.services.toy = {
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                ExecStart = toy;
                StateDirectory = "toy";
              };
            };

            systemd.services.toy-dependent = {
              wantedBy = [ "multi-user.target" ];
              requires = [ "toy.service" ];
              after = [ "toy.service" ];
              serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
            };

            specialisation.v2.configuration = {
              deployState.entries.toy.key = lib.mkForce [ "2" ];
              systemd.services.toy.serviceConfig.ExecStart = lib.mkForce toyV2;
            };
          };

        testScript = ''
          snapshot = "/var/lib/deploy-state-snapshot"
          schema = "/var/lib/toy/schema"

          def toy_pid():
              return machine.succeed("systemctl show --property=MainPID --value toy.service").strip()

          machine.wait_for_unit("toy.service")
          base = machine.succeed("readlink -f /run/current-system").strip()
          v2 = machine.succeed(f"readlink -f {base}/specialisation/v2").strip()
          assert machine.succeed(f"cat {schema}").strip() == "schema=1"

          with subtest("snapshot_changedKey_stopsUnitAndCopiesState"):
              machine.succeed(f"deploy-state-snapshot {base} {v2} {snapshot}")
              machine.fail("systemctl is-active toy.service")
              assert machine.succeed(f"jq -r 'keys[]' {snapshot}/entries.json").strip() == "toy"
              assert machine.succeed(f"cat {snapshot}/toy/0/schema").strip() == "schema=1"
              assert machine.succeed(f"deploy-state-units {snapshot}").strip() == "toy.service"

          with subtest("switch_newSystem_migratesState"):
              machine.succeed(f"{v2}/bin/switch-to-configuration test")
              machine.succeed("systemctl start toy.service")
              machine.wait_for_unit("toy.service")
              assert machine.succeed(f"cat {schema}").strip() == "schema=2"

          with subtest("restore_thenPreviousSystem_runsOnOldState"):
              machine.succeed(f"deploy-state-restore {snapshot}")
              machine.fail("systemctl is-active toy.service")
              assert machine.succeed(f"cat {schema}").strip() == "schema=1"
              machine.succeed(f"{base}/bin/switch-to-configuration test")
              machine.succeed("systemctl start toy.service")
              machine.wait_for_unit("toy.service")
              assert machine.succeed(f"cat {schema}").strip() == "schema=1"

          with subtest("restore_absentPath_removesPath"):
              machine.succeed("systemctl stop toy.service && rm -rf /var/lib/toy")
              machine.succeed(f"deploy-state-snapshot {base} {v2} {snapshot}")
              machine.succeed(f"test -e {snapshot}/toy/0.absent")
              machine.succeed("mkdir -p /var/lib/toy && echo stray > /var/lib/toy/stray")
              machine.succeed(f"deploy-state-restore {snapshot}")
              machine.fail("test -e /var/lib/toy")
              machine.succeed("systemctl start toy.service")
              machine.wait_for_unit("toy.service")
              assert machine.succeed(f"cat {schema}").strip() == "schema=1"

          with subtest("snapshot_sameKey_changesNothing"):
              pid = toy_pid()
              out = machine.succeed(f"deploy-state-snapshot {base} {base} {snapshot}")
              assert "nothing stopped or copied" in out, out
              assert machine.succeed(f"jq -c . {snapshot}/entries.json").strip() == "{}"
              machine.fail(f"test -e {snapshot}/toy")
              machine.succeed("systemctl is-active toy.service")
              assert toy_pid() == pid

          with subtest("snapshot_missingCurrentManifest_snapshotsEverything"):
              machine.succeed("mkdir -p /tmp/empty-system")
              machine.succeed(f"deploy-state-snapshot /tmp/empty-system {base} {snapshot}")
              assert machine.succeed(f"cat {snapshot}/toy/0/schema").strip() == "schema=1"
              machine.succeed(f"{base}/bin/switch-to-configuration test")
              machine.succeed("systemctl start toy.service")
              machine.wait_for_unit("toy.service")

          with subtest("snapshot_copyFails_startsUnitsAgain"):
              machine.succeed("systemctl start toy-dependent.service")
              machine.succeed("mkdir -p /mnt/small && mount -t tmpfs -o size=64k tmpfs /mnt/small")
              machine.succeed("dd if=/dev/zero of=/var/lib/toy/big bs=1M count=1")
              machine.fail(f"deploy-state-snapshot {base} {v2} /mnt/small/snapshot")
              machine.succeed("systemctl is-active toy.service")
              machine.wait_for_unit("toy-dependent.service")
              machine.succeed("rm /var/lib/toy/big && umount /mnt/small")
        '';
      };

      checks.deploy-state-assertion =
        let
          evaluate =
            module:
            let
              system' = lib.nixosSystem {
                modules = [
                  nixos.deploy-state
                  {
                    nixpkgs.hostPlatform = system;
                    system.stateVersion = "26.05";
                    boot.loader.grub.enable = false;
                    fileSystems."/" = {
                      device = "none";
                      fsType = "tmpfs";
                    };
                    deployState = {
                      enforce = true;
                      exempt = baselineExempt;
                    };
                  }
                  module
                ];
              };
            in
            map (assertion: assertion.message) (
              lib.filter (assertion: !assertion.assertion) system'.config.assertions
            );

          cases = {
            unregisteredStateDirectory = {
              module.systemd.services.unregistered.serviceConfig.StateDirectory = "unregistered";
              expected = "/var/lib/unregistered";
            };
            unregisteredDynamicUser = {
              module.systemd.services.dynamic.serviceConfig = {
                DynamicUser = true;
                StateDirectory = "dynamic other/nested";
              };
              expected = "/var/lib/private/other/nested";
            };
            unregisteredContainerVolume = {
              module.virtualisation.oci-containers = {
                backend = "podman";
                containers.volume.image = "example/image";
                containers.volume.volumes = [ "/var/lib/volume/data:/data" ];
              };
              expected = "/var/lib/volume/data";
            };
            unregisteredPostgresql = {
              module.services.postgresql.enable = true;
              expected = "/var/lib/postgresql";
            };
            emptyReason = {
              module.deployState.exempt."/var/lib/anything" = " ";
              expected = "/var/lib/anything";
            };
          };

          covered = {
            module = {
              systemd.services = {
                registered.serviceConfig.StateDirectory = [
                  "registered/nested"
                  "exempted"
                ];
                disabled = {
                  enable = false;
                  serviceConfig.StateDirectory = "disabled";
                };
              };
              deployState = {
                entries.registered = {
                  key = [ "1" ];
                  units = [ "registered.service" ];
                  paths = [ "/var/lib/registered/" ];
                };
                exempt."/var/lib/exempted" = "rebuilt on start";
              };
            };
          };

          results = lib.mapAttrs (_: case: evaluate case.module) cases;
          failures =
            lib.mapAttrsToList (
              name: case:
              if lib.any (lib.hasInfix case.expected) results.${name} then
                null
              else
                "${name}: expected an assertion message naming ${case.expected}, got ${
                  builtins.toJSON results.${name}
                }"
            ) cases
            ++ lib.optional (
              evaluate covered.module != [ ]
            ) "covered: expected no assertion failures, got ${builtins.toJSON (evaluate covered.module)}";
        in
        pkgs.runCommand "deploy-state-assertion"
          { failures = lib.concatStringsSep "\n" (lib.filter (failure: failure != null) failures); }
          ''
            if [ -n "$failures" ]; then
              printf '%s\n' "$failures" >&2
              exit 1
            fi
            touch $out
          '';
    };
}
