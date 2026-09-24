{ config, ... }:
let
  inherit (config.meta) user;
in
{
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    {
      programs.steam = {
        enable = true;
        # Selectable per game under Properties → Compatibility.
        extraCompatPackages = [ pkgs.proton-ge-bin ];
      };

      # Launch option for a game: gamemoderun %command%
      programs.gamemode.enable = true;
      users.users.${user.name}.extraGroups = [ "gamemode" ];

      environment.systemPackages = [ pkgs.faugus-launcher ];
    };
}
