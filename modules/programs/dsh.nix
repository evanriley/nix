{ config, inputs, ... }:
let
  inherit (config.flake.lib) agentScripts mkScript;

  pluginVersions = builtins.fromJSON (builtins.readFile ./dsh-plugins.json);
  tui = rec {
    name = "@deepseek-harness-tui/dsh-tui";
    version = pluginVersions.${name};
  };
  sidebar = rec {
    name = "dsh-better-sidebar";
    version = pluginVersions.${name};
  };
  lockstepPackages = [
    "dsh-hook-protocol"
    "dsh-hooks-claude-code"
    "dsh-lsp"
    "dsh-lsp-stdio"
    "dsh-tool-lsp"
  ];
  base = "@deepseek-ai/dsh-base";
in
{
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.dotfiles) link;
      dsh = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.dsh;
      scripts = agentScripts pkgs;

      lockstepDependencies = lib.genAttrs (map (name: "@deepseek-ai/${name}") lockstepPackages) (
        _: dsh.version
      );

      profiles = {
        dsh-tui = {
          dependencies = lockstepDependencies // {
            ${tui.name} = tui.version;
          };
          bundles = [
            base
            tui.name
          ];
        };
        web = {
          dependencies = lockstepDependencies // {
            ${sidebar.name} = sidebar.version;
          };
          bundles = [
            base
            "@deepseek-ai/dsh-web-app"
            sidebar.name
          ];
        };
      };

      packageJson =
        profile:
        pkgs.writeText "dsh-${profile}-package.json" (
          builtins.toJSON {
            name = "dsh-profile-${profile}";
            private = true;
            inherit (profiles.${profile}) dependencies;
            dsh.profile.bundles = profiles.${profile}.bundles;
          }
        );

      workspaceYaml =
        profile:
        (pkgs.formats.yaml { }).generate "dsh-${profile}-pnpm-workspace.yaml" {
          packages = [ "." ];
          nodeLinker = "hoisted";
          autoInstallPeers = false;
          minimumReleaseAgeExclude = [ "@deepseek-ai/*" ] ++ lib.attrNames profiles.${profile}.dependencies;
          allowBuilds = {
            "@google/genai" = false;
            esbuild = false;
            koffi = false;
            protobufjs = false;
          };
        };

      languageServers = [
        pkgs.nixd
        pkgs.clang-tools
        pkgs.rust-analyzer
        pkgs.zls
        pkgs.basedpyright
        pkgs.ocamlPackages.ocaml-lsp
        pkgs.clojure-lsp
        pkgs.gleam
      ];

      tools = [
        dsh
        pkgs.pnpm
        pkgs.nodejs
        pkgs.jq
      ]
      ++ languageServers;

      mkLauncher =
        {
          name,
          profile,
          prepare ? "",
          run,
        }:
        pkgs.writeShellApplication {
          inherit name;
          text = ''
            PATH="$PATH:${lib.makeBinPath tools}"
            export PATH

            DSH_HOME=''${DSH_HOME:-$HOME/.dsh}
            export DSH_HOME

            read_secret() {
              local file=/run/agenix/$1
              if [ ! -r "$file" ]; then
                echo "dsh: cannot read $file; expected the decrypted agenix secret. Switch this machine's system configuration first." >&2
                exit 1
              fi
              cat "$file"
            }
            ANTHROPIC_API_KEY=$(read_secret anthropic-key)
            OPENROUTER_API_KEY=$(read_secret openrouter-key)
            CORALBRICKS_API_KEY=$(read_secret coralbricks-key)
            KAGI_API_KEY=$(read_secret kagi-key)
            CONTEXT7_API_KEY=$(read_secret context7-key)
            export ANTHROPIC_API_KEY OPENROUTER_API_KEY CORALBRICKS_API_KEY KAGI_API_KEY CONTEXT7_API_KEY
            export DSH_TELEMETRY_MODE=DISABLED
            export PI_CACHE_RETENTION=long

            profile_directory="$DSH_HOME/profiles/${profile}"
            mkdir -p "$profile_directory"
            install -m 0644 ${packageJson profile} "$profile_directory/package.json"
            install -m 0644 ${workspaceYaml profile} "$profile_directory/pnpm-workspace.yaml"
            manifest_hash=$(cat "$profile_directory/package.json" "$profile_directory/pnpm-workspace.yaml" | sha256sum)
            if [ ! -d "$profile_directory/node_modules" ] || [ "$(cat "$profile_directory/.manifest-hash" 2>/dev/null)" != "$manifest_hash" ]; then
              (cd "$profile_directory" && pnpm install)
              printf '%s\n' "$manifest_hash" >"$profile_directory/.manifest-hash"
            fi

            ${prepare}
            exec ${run}
          '';
        };

      blockUpdateCheck = pkgs.writeText "dsh-tui-block-update-check.cjs" ''
        const blocked = /@deepseek-harness-tui\/|ccch1mneyyy/;
        const fetchOriginal = globalThis.fetch;
        globalThis.fetch = (input, init) => {
          const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
          if (blocked.test(url)) {
            return Promise.reject(new TypeError(`blocked by the dsh-tui wrapper: ''${url}`));
          }
          return fetchOriginal(input, init);
        };
      '';

      dshTui = mkLauncher {
        name = "dsh-tui";
        profile = "dsh-tui";
        prepare = ''
          mkdir -p "$HOME/.dsh-tui"
          [ -e "$HOME/.dsh-tui/onboarding.json" ] || printf '%s\n' '{"completed":true,"version":1}' >"$HOME/.dsh-tui/onboarding.json"
        '';
        run = ''env NODE_OPTIONS="--require ${blockUpdateCheck} ''${NODE_OPTIONS:-}" dsh --profile dsh-tui --patch "$DSH_HOME/patches/dsh-tui.cordis.patch.yml" "$@"'';
      };

      dshWeb = mkLauncher {
        name = "dsh-web";
        profile = "web";
        run = ''dsh --profile web --patch "$DSH_HOME/patches/web.cordis.patch.yml" "$@"'';
      };

      hooks = pkgs.writeText "dsh-hooks.json" (
        builtins.toJSON {
          hooks = {
            PreToolUse = [
              {
                matcher = "bash";
                hooks = [
                  {
                    type = "command";
                    command = lib.getExe scripts.agent-no-kill;
                  }
                ];
              }
            ];
            PostToolUse = [
              {
                matcher = "edit|write";
                hooks = [
                  {
                    type = "command";
                    command = lib.getExe scripts.agent-format;
                  }
                ];
              }
            ];
            Stop = [
              {
                hooks = [
                  {
                    type = "command";
                    command = "AGENT_NOTIFY_APP=dsh ${lib.getExe scripts.agent-notify}";
                  }
                ];
              }
            ];
          };
        }
      );
    in
    {
      home.packages = [
        dshTui
        dshWeb
        (mkScript pkgs {
          name = "dsh-openrouter-presets";
          src = ./_ai/dsh-openrouter-presets;
          runtimeInputs = [
            pkgs.curl
            pkgs.jq
          ];
        })
      ];

      home.file = {
        ".dsh/AGENTS.md".source = link "config/ai/dsh/AGENTS.md";
        ".dsh/cordis.patch.yml".source = link "config/ai/dsh/cordis.patch.yml";
        ".dsh/hooks.json".source = hooks;
        ".dsh/patches/dsh-tui.cordis.patch.yml".source =
          link "config/ai/dsh/profiles/dsh-tui.cordis.patch.yml";
        ".dsh/patches/web.cordis.patch.yml".source = link "config/ai/dsh/profiles/web.cordis.patch.yml";
      };
    };

  perSystem =
    { pkgs, ... }:
    let
      newestCompatible = pkgs.writeText "dsh-plugins-newest-compatible.cjs" ''
        const semver = require("${pkgs.nodejs}/lib/node_modules/npm/node_modules/semver");
        const [current, dshVersion] = process.argv.slice(2);
        let input = "";
        process.stdin.on("data", (chunk) => (input += chunk));
        process.stdin.on("end", () => {
          const compatible = Object.entries(JSON.parse(input).versions)
            .filter(([version, manifest]) => {
              if (!semver.valid(version) || semver.prerelease(version)) return false;
              return Object.entries(manifest.peerDependencies ?? {})
                .filter(([name]) => name.startsWith("@deepseek-ai/dsh-"))
                .every(([, range]) => semver.satisfies(dshVersion, range));
            })
            .map(([version]) => version)
            .sort(semver.compare);
          const newest = compatible.at(-1);
          console.log(newest !== undefined && semver.gt(newest, current) ? newest : current);
        });
      '';
    in
    {
      packages.dsh-plugins-update = pkgs.writeShellApplication {
        name = "dsh-plugins-update";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.jq
          pkgs.nodejs
        ];
        text = ''
          if [ "$#" -ne 2 ]; then
            echo "usage: dsh-plugins-update <dsh-plugins.json> <dsh version>" >&2
            exit 2
          fi
          plugins_file=$1
          dsh_version=$2

          if ! names=$(jq -er 'keys_unsorted[]' "$plugins_file"); then
            echo "reading the plugin names from $plugins_file failed; expected a JSON object of package names to versions. Check the file, then run dsh-plugins-update again" >&2
            exit 1
          fi

          new=$(<"$plugins_file")
          summary=
          while IFS= read -r name; do
            current=$(jq -er --arg name "$name" '.[$name]' "$plugins_file")
            if ! metadata=$(curl -fsS "https://registry.npmjs.org/$name"); then
              echo "fetching $name from registry.npmjs.org failed; $plugins_file is unchanged. Check the network, then run dsh-plugins-update again" >&2
              exit 1
            fi
            if ! latest=$(node ${newestCompatible} "$current" "$dsh_version" <<<"$metadata"); then
              echo "selecting a version of $name compatible with dsh $dsh_version failed; $plugins_file is unchanged. Check the registry metadata of $name, then run dsh-plugins-update again" >&2
              exit 1
            fi
            if [ "$latest" != "$current" ]; then
              new=$(jq --arg name "$name" --arg version "$latest" '.[$name] = $version' <<<"$new")
              summary+="$name $current -> $latest"$'\n'
            fi
          done <<<"$names"

          if [ -z "$summary" ]; then
            echo "dsh plugins are up to date for dsh $dsh_version"
            exit 0
          fi

          temporary=$(mktemp)
          printf '%s\n' "$new" >"$temporary"
          chmod --reference="$plugins_file" "$temporary"
          mv "$temporary" "$plugins_file"
          printf '%s' "$summary"
        '';
      };

      checks.dsh-config =
        pkgs.runCommand "dsh-config-check"
          {
            nativeBuildInputs = [
              pkgs.bash
              pkgs.jq
              pkgs.yq-go
            ];
          }
          ''
            bash ${./_ai/test-dsh} ${../../home/config/ai/dsh} ${./_ai/dsh-openrouter-presets}
            touch $out
          '';
    };
}
