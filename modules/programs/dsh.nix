{ config, inputs, ... }:
let
  inherit (config.flake.lib) agentScripts mkScript;

  tui = {
    name = "@deepseek-harness-tui/dsh-tui";
    version = "0.17.0";
  };
  sidebar = {
    name = "dsh-better-sidebar";
    version = "0.28.0";
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
            OPENROUTER_API_KEY=$(read_secret openrouter-key)
            CORALBRICKS_API_KEY=$(read_secret coralbricks-key)
            KAGI_API_KEY=$(read_secret kagi-key)
            CONTEXT7_API_KEY=$(read_secret context7-key)
            export OPENROUTER_API_KEY CORALBRICKS_API_KEY KAGI_API_KEY CONTEXT7_API_KEY
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
        run = ''env NODE_OPTIONS="--require ${blockUpdateCheck} ''${NODE_OPTIONS:-}" dsh --profile dsh-tui "$@"'';
      };

      dshWeb = mkLauncher {
        name = "dsh-web";
        profile = "web";
        run = ''dsh --profile web "$@"'';
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
        ".dsh/profiles/dsh-tui/cordis.patch.yml".source =
          link "config/ai/dsh/profiles/dsh-tui.cordis.patch.yml";
        ".dsh/profiles/web/cordis.patch.yml".source = link "config/ai/dsh/profiles/web.cordis.patch.yml";
      };
    };

  perSystem =
    { pkgs, ... }:
    {
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
