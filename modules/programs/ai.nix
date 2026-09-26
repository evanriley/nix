{ inputs, ... }:
{
  flake.modules.homeManager.ai =
    { config, lib, ... }:
    let
      inherit (config.dotfiles) link;
      ownSkills = lib.mapAttrs (name: _: link "config/ai/skills/${name}") (
        lib.filterAttrs (_: type: type == "directory") (
          builtins.readDir (inputs.self + "/home/config/ai/skills")
        )
      );
      skills = ownSkills // {
        skill-creator = inputs.anthropic-skills + "/skills/skill-creator";
      };
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

      home.file = {
        ".claude/CLAUDE.md".source = link "config/ai/AGENTS.md";
        ".claude/settings.json".source = link "config/ai/claude/settings.json";
        ".codex/AGENTS.md".source = link "config/ai/AGENTS.md";
      }
      // linkSkills ".claude/skills"
      // linkSkills ".agents/skills";
    };
}
