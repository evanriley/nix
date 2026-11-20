{
  flake.modules.nixos.deploy-state =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.deployState;

      manifestPath = "deploy-state/manifest.json";

      manifest = lib.mapAttrs (
        _:
        lib.getAttrs [
          "key"
          "units"
          "paths"
        ]
      ) cfg.entries;

      stateDirectoryPaths = lib.concatLists (
        lib.mapAttrsToList (
          _: service:
          let
            raw = service.serviceConfig.StateDirectory or [ ];
            names = lib.filter (name: name != "") (lib.concatMap (lib.splitString " ") (lib.toList raw));
            root = if service.serviceConfig.DynamicUser or false then "/var/lib/private" else "/var/lib";
          in
          map (name: "${root}/${name}") names
        ) (lib.filterAttrs (_: service: service.enable) config.systemd.services)
      );

      containerVolumePaths = lib.filter (lib.hasPrefix "/var/lib/") (
        lib.concatMap (container: map (volume: lib.head (lib.splitString ":" volume)) container.volumes) (
          lib.attrValues config.virtualisation.oci-containers.containers
        )
      );

      postgresqlPaths = lib.optional config.services.postgresql.enable config.services.postgresql.dataDir;

      discoveredPaths = lib.unique (stateDirectoryPaths ++ containerVolumePaths ++ postgresqlPaths);

      coveringPaths = map (lib.removeSuffix "/") (
        lib.concatMap (entry: entry.paths) (lib.attrValues cfg.entries) ++ lib.attrNames cfg.exempt
      );

      isCovered =
        path:
        let
          normalized = lib.removeSuffix "/" path;
        in
        lib.any (covering: normalized == covering || lib.hasPrefix "${covering}/" normalized) coveringPaths;

      uncoveredPaths = lib.filter (path: !isCovered path) discoveredPaths;

      emptyReasons = lib.attrNames (
        lib.filterAttrs (_: reason: builtins.match "[[:space:]]*" reason != null) cfg.exempt
      );

      snapshot = pkgs.writeShellApplication {
        name = "deploy-state-snapshot";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
          config.systemd.package
        ];
        text = ''
          if [ "$#" -ne 3 ]; then
            echo "usage: deploy-state-snapshot <current-system> <new-system> <dir>" >&2
            exit 2
          fi
          current=$1
          new=$2
          dir=$3
          current_manifest=$current/etc/${manifestPath}
          new_manifest=$new/etc/${manifestPath}

          if [ ! -r "$new_manifest" ]; then
            echo "$new_manifest does not exist, expected a NixOS system closure that imports nixos.deploy-state. Import it in that host, then build the system again" >&2
            exit 1
          fi
          if [ -r "$current_manifest" ]; then
            if ! current_json=$(jq -c . "$current_manifest"); then
              echo "$current_manifest is not valid JSON, expected the manifest written by nixos.deploy-state. Inspect the file, then run deploy-state-snapshot again" >&2
              exit 1
            fi
          else
            current_json='{}'
          fi
          if ! changed=$(jq -c --argjson current "$current_json" \
            'with_entries(select(.value.key != ($current[.key].key // null)))' "$new_manifest"); then
            echo "$new_manifest is not valid JSON, expected the manifest written by nixos.deploy-state. Inspect the file, then run deploy-state-snapshot again" >&2
            exit 1
          fi

          rm -rf -- "$dir"
          mkdir -p -- "$dir"
          printf '%s\n' "$changed" | jq . > "$dir/entries.json"

          if [ "$(jq length "$dir/entries.json")" -eq 0 ]; then
            echo "no registered state has a changed key between $current and $new; nothing stopped or copied"
            exit 0
          fi

          mapfile -t units < <(jq -r '[.[].units[]] | unique[]' "$dir/entries.json")
          start_units() {
            if [ "''${#units[@]}" -gt 0 ]; then
              systemctl start -- "''${units[@]}" default.target || true
            fi
          }

          echo "changed state: $(jq -r 'keys | join(", ")' "$dir/entries.json")"
          if [ "''${#units[@]}" -gt 0 ]; then
            echo "stopping ''${units[*]}"
            if ! systemctl stop -- "''${units[@]}"; then
              start_units
              echo "systemctl stop ''${units[*]} failed; expected every unit of the changed state to stop before it is copied. Check systemctl status ''${units[*]}, then run the deploy again; nothing was switched" >&2
              exit 1
            fi
          fi

          mapfile -t copies < <(jq -r 'to_entries[] | .key as $name | .value.paths | to_entries[] | [$name, (.key | tostring), .value] | @tsv' "$dir/entries.json")
          for copy in "''${copies[@]}"; do
            IFS=$'\t' read -r name index path <<< "$copy"
            mkdir -p -- "$dir/$name"
            if [ -e "$path" ] || [ -L "$path" ]; then
              echo "copying $path to $dir/$name/$index"
              if ! cp -a -- "$path" "$dir/$name/$index"; then
                start_units
                echo "cp -a -- $path $dir/$name/$index failed; expected a full copy of the state of $name. Free space on $(dirname "$dir") or fix the permissions of $path, then run the deploy again; nothing was switched and the units were started again" >&2
                exit 1
              fi
            else
              echo "$path does not exist; recording it as absent"
              touch -- "$dir/$name/$index.absent"
            fi
          done
        '';
      };

      restore = pkgs.writeShellApplication {
        name = "deploy-state-restore";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
          config.systemd.package
        ];
        text = ''
          if [ "$#" -ne 1 ]; then
            echo "usage: deploy-state-restore <dir>" >&2
            exit 2
          fi
          dir=$1
          if [ ! -r "$dir/entries.json" ]; then
            echo "$dir/entries.json does not exist, expected a directory written by deploy-state-snapshot. Check the directory, then run deploy-state-restore again" >&2
            exit 1
          fi

          mapfile -t units < <(jq -r '[.[].units[]] | unique[]' "$dir/entries.json")
          if [ "''${#units[@]}" -gt 0 ]; then
            echo "stopping ''${units[*]}"
            if ! systemctl stop -- "''${units[@]}"; then
              echo "systemctl stop ''${units[*]} failed; expected every unit of the snapshotted state to stop before it is restored. Check systemctl status ''${units[*]}, then run deploy-state-restore $dir again" >&2
              exit 1
            fi
          fi

          mapfile -t copies < <(jq -r 'to_entries[] | .key as $name | .value.paths | to_entries[] | [$name, (.key | tostring), .value] | @tsv' "$dir/entries.json")
          status=0
          for copy in "''${copies[@]}"; do
            IFS=$'\t' read -r name index path <<< "$copy"
            source=$dir/$name/$index
            if [ ! -e "$source" ] && [ ! -L "$source" ] && [ ! -e "$source.absent" ]; then
              echo "$source and $source.absent do not exist, expected the snapshot of $path. Restore $path from the borg backup" >&2
              status=1
              continue
            fi
            echo "restoring $path"
            if ! rm -rf -- "$path"; then
              echo "rm -rf -- $path failed; expected the path to be removed before it is restored. Fix the permissions, then run: rm -rf -- $path && cp -a -- $source $path" >&2
              status=1
              continue
            fi
            if [ -e "$source.absent" ]; then
              continue
            fi
            if ! mkdir -p -- "$(dirname "$path")" || ! cp -a -- "$source" "$path"; then
              echo "cp -a -- $source $path failed; expected a full restore of $path. Free space or fix the permissions, then run: rm -rf -- $path && cp -a -- $source $path" >&2
              status=1
            fi
          done
          exit "$status"
        '';
      };

      units = pkgs.writeShellApplication {
        name = "deploy-state-units";
        runtimeInputs = [ pkgs.jq ];
        text = ''
          if [ "$#" -ne 1 ]; then
            echo "usage: deploy-state-units <dir>" >&2
            exit 2
          fi
          if [ ! -r "$1/entries.json" ]; then
            echo "$1/entries.json does not exist, expected a directory written by deploy-state-snapshot" >&2
            exit 1
          fi
          jq -r '[.[].units[]] | unique[]' "$1/entries.json"
        '';
      };
    in
    {
      options.deployState = {
        entries = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                key = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  description = "Strings such as store paths, versions or image references; a change means the service may have migrated its state.";
                };
                units = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  description = "Units that write the paths; stopped while the paths are copied or restored.";
                };
                paths = lib.mkOption {
                  type = lib.types.listOf (lib.types.strMatching "/.*");
                  description = "Absolute paths copied before a deploy that changed the key and restored on rollback.";
                };
              };
            }
          );
          default = { };
          description = "Stateful services whose on-disk state a rollback restores.";
        };
        exempt = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "State paths that need no snapshot, each with the reason.";
        };
        enforce = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Fail evaluation when a service state path is neither registered in deployState.entries nor listed in deployState.exempt.";
        };
        commands = lib.mkOption {
          type = lib.types.attrsOf lib.types.package;
          readOnly = true;
          default = {
            inherit snapshot restore units;
          };
          description = "The deploy-state-snapshot, deploy-state-restore and deploy-state-units commands.";
        };
      };

      config = {
        assertions = [
          {
            assertion = !cfg.enforce || uncoveredPaths == [ ];
            message = "These state paths are neither registered in deployState.entries nor listed in deployState.exempt: ${lib.concatStringsSep ", " uncoveredPaths}. A rollback restores code but not state, so add a deployState.entries entry (key, units, paths) for each service that can migrate its state, or a deployState.exempt reason for state that needs no snapshot";
          }
          {
            assertion = emptyReasons == [ ];
            message = "deployState.exempt has an empty reason for: ${lib.concatStringsSep ", " emptyReasons}; expected the reason the path needs no snapshot";
          }
        ];

        environment.etc.${manifestPath}.text = builtins.toJSON manifest;

        environment.systemPackages = lib.attrValues cfg.commands;
      };
    };
}
