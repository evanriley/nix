{config, pkgs, ...}:

{
  imports = [
    ./hardware.nix
    ./packages.nix
    ./shell.nix
    ./users.nix
    ./xserver.nix
    ./wayland.nix
  ];

#  nixpkgs.overlays = import ../../pkgs/overlays;

  nix = {
    daemonIONiceLevel = 8;
    daemonNiceLevel = 19;
    useSandbox = true;
    extraOptions = ''
      fallback = true
    '';

  };

  # i18n properties
  console.keyMap = "us";
  i18n.defaultLocale = "en_US.UTF-8";

  # Time Zone
  time.timeZone = "America/New_York";

  # The NixOS release version
  system.stateVersion = "20.03";

}
