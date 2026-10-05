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
      services.borgmatic.configurations.home.exclude_patterns = map (path: "${home}/${path}") [
        ".unsloth"
        ".xlcore"
        ".local/share/containers/storage"
        ".local/share/orca"
        ".var/app/ai.lmstudio.lm-studio"
        "Developer/cports/bldroot"
        "Developer/cports/packages"
        "Developer/cports/sources"
        "Developer/orca/.zig-cache"
        "Developer/orca/zig-out"
        "Developer/qbz/crates/target"
        "Developer/Strata/Strata-data"
      ];

      services.snapper.configs.home = {
        SUBVOLUME = "/home";
        ALLOW_USERS = [ user.name ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
      };
    };
}
