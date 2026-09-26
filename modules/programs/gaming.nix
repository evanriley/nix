{ config, ... }:
let
  inherit (config.meta) user;
  inherit (config.flake.lib) sessionService;
in
{
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    {
      programs.steam.enable = true;
      # No capSysNice: Steam's sandbox then refuses to start gamescope (nixpkgs#351516).
      programs.gamescope.enable = true;

      programs.gamemode.enable = true;
      users.users.${user.name}.extraGroups = [ "gamemode" ];

      environment.systemPackages = [ pkgs.faugus-launcher ];

      boot.kernelModules = [ "ntsync" ];
      services.udev.extraRules = ''
        KERNEL=="ntsync", MODE="0666"
      '';

      boot.kernel.sysctl."kernel.split_lock_mitigate" = 0;
    };

  flake.modules.homeManager.gaming =
    { pkgs, ... }:
    {
      # Steam and Faugus both list compatibilitytools.d. Not named GE-Proton: umu
      # treats that name as "download the latest GE-Proton".
      home.file.".local/share/Steam/compatibilitytools.d/GE-Proton-Nix".source =
        pkgs.proton-ge-bin.steamcompattool;

      # Not niri spawn-at-startup: it dies in a race at login and niri discards its output.
      systemd.user.services.steam = sessionService {
        description = "Steam";
        exec = "/run/current-system/sw/bin/steam -silent";
      };

      programs.mangohud = {
        enable = true;
        settings = {
          toggle_hud = "Shift_R+F12";
          position = "top-left";
          fps = true;
          frametime = true;
          frame_timing = true;
          gpu_stats = true;
          gpu_temp = true;
          gpu_power = true;
          cpu_stats = true;
          cpu_temp = true;
          ram = true;
          vram = true;
        };
      };
    };
}
