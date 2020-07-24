{ config, pkgs, ... }:

{
  # Disable mutable users
  users.mutableUsers = false;

  # Allow paswwordless sudo for wheel users
  security.sudo.wheelNeedsPassword = false;

  # user accounts

  users.extraUsers.evan = {
    createHome = true;
    extraGroups = [ "wheel" "video" "audio" "disk" "networkmanager" "plugdev" ];
    hashedPassword = "$6$LdkF57.B3ZTmBmk6$SCn9Pvl4SwEsqruo7aJVbZG6uowLYHcX82oRGRlzxhf5CxFv0.p4mVZBOMFyzQY8MWf0Uc6.RjiOpFius2Zvt/";
    home = "/home/evan";
    shell = pkgs.zsh;
    isNormalUser = true;
    uid = 1000;
  };



}
