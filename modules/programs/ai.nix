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
        ".codex/AGENTS.md".source = link "config/ai/AGENTS.md";
      }
      // linkSkills ".claude/skills"
      // linkSkills ".agents/skills";

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
        run install -m 600 /dev/stdin "$settings" <<<"$merged"
      '';
    };
}
