{
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    {
      programs.steam.enable = true;

      environment.systemPackages = [ pkgs.faugus-launcher ];
    };
}
