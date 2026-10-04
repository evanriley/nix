{ config, inputs, ... }:
let
  inherit (config.flake.lib) mkScript;
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
      skills = lib.mapAttrs (name: _: link "config/ai/skills/${name}") (
        lib.filterAttrs (_: type: type == "directory") (
          builtins.readDir (inputs.self + "/home/config/ai/skills")
        )
      );
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
          effort = "medium";
        };
        worker-high = {
          model = "gpt-6.1-sol";
          effort = "xhigh";
        };
      };
      readClaudeAgent =
        role:
        let
          lines = lib.splitString "\n" (
            builtins.readFile (inputs.self + "/home/config/ai/claude/agents/${role}.md")
          );
          afterOpening = lib.tail lines;
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
            "worker-high"
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
        (mkScript pkgs {
          name = "agent-notify";
          src = ./_ai/agent-notify;
          runtimeInputs = [ pkgs.jq ] ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.libnotify;
        })
        (mkScript pkgs {
          name = "agent-no-kill";
          src = ./_ai/agent-no-kill;
          runtimeInputs = [ pkgs.jq ];
        })
        (mkScript pkgs {
          name = "agent-format";
          src = ./_ai/agent-format;
          runtimeInputs = [
            pkgs.jq
            pkgs.nixfmt
          ];
        })
      ];

      home.file = {
        ".claude/CLAUDE.md".source = link "config/ai/AGENTS.md";
        ".claude/agents".source = link "config/ai/claude/agents";
        ".codex/AGENTS.md".source = link "config/ai/AGENTS.md";
      }
      // linkSkills ".claude/skills"
      // linkSkills ".agents/skills"
      // codexAgentFiles;

      # Claude Code refuses to save settings through a symlink, so settings.json is
      # a real file: the keys from the repository win, the rest is Claude Code's.
      home.activation.claudeSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        settings="$HOME/.claude/settings.json"
        managed=${../../home/config/ai/claude/settings.json}
        [ -L "$settings" ] && run rm "$settings"
        current='{}'
        [ -f "$settings" ] && current=$(cat "$settings")
        merged=$(${lib.getExe pkgs.jq} -s '.[0] * .[1]' <(printf '%s' "$current") "$managed") || {
          errorEcho "Failed to merge $managed into $settings; expected valid JSON in both. Fix or remove $settings, then switch again."
          exit 1
        }
        run mkdir -p "$HOME/.claude"
        # macOS install cannot copy from /dev/stdin.
        tmp=$(mktemp)
        printf '%s\n' "$merged" >"$tmp"
        run install -m 600 "$tmp" "$settings"
        rm -f "$tmp"
      '';

      home.activation.codexConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run mkdir -p "$HOME/.codex"
        run ${mergeToml} ${../../home/config/ai/codex/config.toml} "$HOME/.codex/config.toml"
      '';
    };
}
