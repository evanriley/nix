{ config, inputs, ... }:
let
  inherit (config.flake.lib) mkScript;
  inherit (config.meta) user secrets;
  openrouterKey = {
    file = secrets + "/openrouter-key.age";
    owner = user.name;
  };
  anthropicKey = {
    file = secrets + "/anthropic-key.age";
    owner = user.name;
  };
  kagiKey = {
    file = secrets + "/kagi-key.age";
    owner = user.name;
  };
  context7Key = {
    file = secrets + "/context7-key.age";
    owner = user.name;
  };
  coralbricksKey = {
    file = secrets + "/coralbricks-key.age";
    owner = user.name;
  };
  agentScripts = pkgs: {
    agent-notify = mkScript pkgs {
      name = "agent-notify";
      src = ./_ai/agent-notify;
      runtimeInputs = [ pkgs.jq ] ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.libnotify;
    };
    agent-no-kill = mkScript pkgs {
      name = "agent-no-kill";
      src = ./_ai/agent-no-kill;
      runtimeInputs = [ pkgs.jq ];
    };
    agent-format = mkScript pkgs {
      name = "agent-format";
      src = ./_ai/agent-format;
      runtimeInputs = [
        pkgs.jq
        pkgs.nixfmt
      ];
    };
  };
  codexRoles = {
    search = {
      model = "gpt-6-luna";
      effort = "medium";
    };
    librarian = {
      model = "gpt-6.1-sol";
      effort = "medium";
    };
    oracle = {
      model = "gpt-6-astra";
      effort = "xhigh";
    };
    worker = {
      model = "gpt-6.1-sol";
      effort = "high";
    };
    senior = {
      model = "gpt-6-astra";
      effort = "high";
    };
    principal = {
      model = "gpt-6-astra";
      effort = "xhigh";
    };
  };
in
{
  flake.lib.agentScripts = agentScripts;

  flake.modules.nixos.ai.age.secrets = {
    openrouter-key = openrouterKey;
    anthropic-key = anthropicKey;
    kagi-key = kagiKey;
    context7-key = context7Key;
    coralbricks-key = coralbricksKey;
  };

  flake.modules.darwin.ai.age.secrets = {
    openrouter-key = openrouterKey;
    anthropic-key = anthropicKey;
    kagi-key = kagiKey;
    context7-key = context7Key;
    coralbricks-key = coralbricksKey;
  };

  flake.modules.homeManager.ai =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.dotfiles) link;
      skills = lib.mapAttrs (name: _: link "config/ai/skills/${name}") (
        lib.filterAttrs (_: type: type == "directory") (
          builtins.readDir (inputs.self + "/home/config/ai/skills")
        )
      );
      readClaudeAgent =
        role:
        let
          lines = lib.splitString "\n" (
            builtins.readFile (inputs.self + "/home/config/ai/claude/agents/${role}.md")
          );
          afterOpening =
            if lib.head lines == "---" then
              lib.tail lines
            else
              throw "${role}.md has no opening frontmatter line";
          closingIndex = lib.lists.findFirstIndex (
            line: line == "---"
          ) (throw "${role}.md has no closing frontmatter line") afterOpening;
          frontmatter = lib.take closingIndex afterOpening;
          descriptionLine =
            lib.findFirst (lib.hasPrefix "description: ") (throw "${role}.md has no description")
              frontmatter;
        in
        {
          description = lib.removeSuffix "\"" (lib.removePrefix "description: \"" descriptionLine);
          body = lib.trim (lib.concatStringsSep "\n" (lib.drop (closingIndex + 1) afterOpening));
        };
      codexAgentFiles = lib.mapAttrs' (
        role: settings:
        let
          agent = readClaudeAgent role;
          guidelines = lib.optionalString (lib.elem role [
            "worker"
            "senior"
            "principal"
          ]) "Load the `code-guidelines` skill before editing.\n\n";
        in
        lib.nameValuePair ".codex/agents/${role}.toml" {
          source = (pkgs.formats.toml { }).generate "${role}.toml" {
            name = role;
            inherit (agent) description;
            developer_instructions = guidelines + agent.body;
            inherit (settings) model;
            model_reasoning_effort = settings.effort;
          };
        }
      ) codexRoles;
      pythonWithTomlkit = pkgs.python3.withPackages (python: [ python.tomlkit ]);
      mergeToml = "${lib.getExe pythonWithTomlkit} ${./_ai/merge-toml}";
      mergeClaudeSettings = "${./_ai/merge-claude-settings}";
      pi = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;
      piWithLongCache = pkgs.symlinkJoin {
        name = "pi-${pi.version}";
        paths = [ pi ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/pi --set PI_CACHE_RETENTION long
        '';
        meta.mainProgram = "pi";
      };
      mergeSettings =
        {
          directory,
          managed,
          label,
        }:
        ''
          settings="${directory}/settings.json"
          managed=${managed}
          [ -L "$settings" ] && run rm "$settings"
          ownership="${directory}/.managed-settings.json"
          current=$(mktemp)
          previous=$(mktemp)
          [ -f "$settings" ] && cat "$settings" >"$current" || printf '{}\n' >"$current"
          [ -f "$ownership" ] && cat "$ownership" >"$previous" || cat "$managed" >"$previous"
          merged=$(${lib.getExe pkgs.bash} ${mergeClaudeSettings} "$current" "$previous" "$managed") || {
            errorEcho "Failed to merge $managed into $settings for ${label}; expected valid JSON in both. Fix or remove $settings, then switch again."
            rm -f "$current" "$previous"
            exit 1
          }
          rm -f "$current" "$previous"
          run mkdir -p "${directory}"
          # macOS install cannot copy from /dev/stdin.
          tmp=$(mktemp)
          printf '%s\n' "$merged" >"$tmp"
          run install -m 600 "$tmp" "$settings"
          run install -m 600 "$managed" "$ownership"
          rm -f "$tmp"
        '';
      # Per skill, because claude.ai keeps its synced skills in ~/.claude/skills.
      linkSkills =
        dir:
        lib.mapAttrs' (name: source: {
          name = "${dir}/${name}";
          value = { inherit source; };
        }) skills;
    in
    {
      dotfiles.config = [ "ai" ];

      home.packages = [
        piWithLongCache
      ]
      ++ lib.attrValues (agentScripts pkgs);

      programs.git.includes = [
        {
          condition = "gitdir:~/maybe/";
          contents.pi.featureBranches = false;
        }
      ];

      home.file = {
        ".claude/CLAUDE.md".source = link "config/ai/AGENTS.md";
        ".claude/agents".source = link "config/ai/claude/agents";
        ".codex/AGENTS.md".source = link "config/ai/AGENTS.md";
        ".pi/agent/models.json".source = link "config/ai/pi/models.json";
        ".pi/agent/mcp.json".source = link "config/ai/pi/mcp.json";
        ".pi/agent/AGENTS.md".source = link "config/ai/pi/AGENTS.md";
        ".pi/agent/prompts".source = link "config/ai/pi/prompts";
        ".pi/agent/extensions/loop".source = link "config/ai/pi/extensions/loop";
        ".pi/agent/extensions/exit.ts".source = link "config/ai/pi/extensions/exit.ts";
        ".pi/agent/extensions/guard".source = link "config/ai/pi/extensions/guard";
        ".pi/agent/extensions/vision".source = link "config/ai/pi/extensions/vision";
        ".pi/agent/extensions/oracle".source = link "config/ai/pi/extensions/oracle";
      }
      // linkSkills ".claude/skills"
      // linkSkills ".agents/skills"
      // codexAgentFiles;

      # Claude Code refuses to save settings through a symlink, so settings.json is
      # a real file: the keys from the repository win, the rest is Claude Code's.
      home.activation.claudeSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] (mergeSettings {
        directory = "$HOME/.claude";
        managed = ../../home/config/ai/claude/settings.json;
        label = "claude";
      });

      home.activation.piSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] (mergeSettings {
        directory = "$HOME/.pi/agent";
        managed = ../../home/config/ai/pi/settings.json;
        label = "pi";
      });

      home.activation.codexConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run mkdir -p "$HOME/.codex"
        run ${mergeToml} ${../../home/config/ai/codex/config.toml} "$HOME/.codex/config.toml"
      '';
    };

  perSystem =
    { pkgs, ... }:
    let
      roles = builtins.concatStringsSep " " (builtins.attrNames codexRoles);

      nodeTypes = pkgs.stdenv.mkDerivation {
        pname = "node-types";
        version = "26.6.5";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/@types/node/-/node-26.6.5.tgz";
          hash = "sha256-5OR9rIYEaapap5BDprgzlimdnNbuI7MPyyB0YlrI298=";
        };
        dontUnpack = true;
        installPhase = ''
          mkdir -p $out
          tar -xzf $src -C $out
        '';
      };
    in
    {
      checks.ai-config =
        pkgs.runCommand "ai-config-check"
          {
            nativeBuildInputs = [
              pkgs.bash
              pkgs.jq
              pkgs.python3
            ];
          }
          ''
            ${pkgs.bash}/bin/bash ${./_ai/test-ai} \
              ${../../home/config/ai/claude/agents} \
              ${./_ai/agent-no-kill} \
              ${./_ai/agent-format} \
              ${./_ai/merge-claude-settings} \
              ${pkgs.lib.escapeShellArg roles}
            touch $out
          '';

      checks.ai-extensions =
        pkgs.runCommand "ai-extensions-check"
          {
            nativeBuildInputs = [
              pkgs.git
              pkgs.nodejs
              pkgs.typescript
            ];
          }
          ''
            cp -r ${../../home/config/ai/pi/extensions} extensions
            chmod -R u+w extensions
            cp ${./_ai/extensions-stubs.d.ts} extensions/stubs.d.ts
            cd extensions

            # The sandbox has no /usr/bin/env, so the hooks the suite writes
            # could not start bash there.
            sed -i 's|#!/usr/bin/env bash|#!${pkgs.bash}/bin/bash|' loop/pipeline.test.ts

            tsc --noEmit \
              --skipLibCheck \
              --allowImportingTsExtensions \
              --target esnext \
              --module esnext \
              --moduleResolution bundler \
              --noImplicitAny false \
              --types node \
              --typeRoots ${nodeTypes} \
              stubs.d.ts \
              guard/index.ts \
              guard/rules.ts \
              loop/index.ts \
              loop/pipeline.ts \
              oracle/index.ts \
              vision/index.ts \
              exit.ts

            node --test guard/rules.test.ts loop/pipeline.test.ts

            touch $out
          '';
    };
}
