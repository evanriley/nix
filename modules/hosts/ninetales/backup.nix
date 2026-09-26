{ config, ... }:
let
  inherit (config.meta) user;
in
{
  flake.modules.darwin.ninetales =
    { config, ... }:
    let
      home = config.users.users.${user.name}.home;
    in
    {
      services.borgmatic.configurations.home.exclude_patterns = [
        "${home}/Library/Mobile Documents"
      ]
      ++ map (path: "sh:${home}/Library/Application Support/org.nixos.firefox/Profiles/*/${path}") [
        "cache2"
        "startupCache"
        "safebrowsing"
      ];
    };
}
