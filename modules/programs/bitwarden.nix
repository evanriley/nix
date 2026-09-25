{ config, ... }:
let
  inherit (config.meta) user;
in
{
  flake.modules.homeManager.bitwarden =
    { pkgs, ... }:
    {
      programs.rbw = {
        enable = true;
        settings = {
          inherit (user) email;
          lock_timeout = 43200;
          sync_interval = 900;
          pinentry = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.pinentry_mac else pkgs.pinentry-gnome3;
        };
      };
    };
}
