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

      boot.kernelModules = [ "ntsync" ];
      services.udev.extraRules = ''
        KERNEL=="ntsync", MODE="0666"
      '';

      boot.kernel.sysctl."kernel.split_lock_mitigate" = 0;
    };
}
