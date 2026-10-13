{ config, ... }:
let
  inherit (config.meta) user;
in
{
  flake.modules.nixos.cinderace =
    { config, ... }:
    let
      home = config.users.users.${user.name}.home;
    in
    {
      services.borgmatic.configurations.home.exclude_patterns =
        map (path: "${home}/${path}") [
          ".claude"
          ".codex"
          ".unsloth"
          ".xlcore"
          "go"
          "Faugus/battlenet"
          ".local/share/containers/storage"
          ".local/share/orca"
          ".local/share/Steam/compatibilitytools.d"
          ".local/share/Steam/package"
          ".local/share/Steam/steamapps"
          ".local/share/Steam/steamrt64"
          ".local/share/Steam/ubuntu12_32"
          ".local/share/Steam/ubuntu12_64"
          ".var/app/ai.lmstudio.lm-studio"
          "Developer/cports/bldroot"
          "Developer/cports/packages"
          "Developer/cports/sources"
          "Developer/orca/.zig-cache"
          "Developer/orca/zig-out"
          "Developer/qbz/crates/target"
          "Developer/Strata/Strata-data"
        ]
        ++ [
          "sh:${home}/Developer/**/.zig-cache"
          "sh:${home}/Developer/**/zig-out"
          "sh:${home}/Developer/**/.claude/worktrees"
        ];

      services.snapper.configs.home = {
        SUBVOLUME = "/home";
        ALLOW_USERS = [ user.name ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = 2;
      };
    };
}
