{config, pkgs, ... }:

{
  services.xserver = {
    # enable the x11 windowing system
    enable = true;
    layout = "us";
    xkbOptions = "caps:control";
    autoRepeatDelay = 300;
    autoRepeatInterval = 30;

    # Use SDDM as my display manager
    displayManager.sddm = {
      enable = true;
    };
  };

}
