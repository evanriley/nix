{config, pkgs, lib, ...}:

{
  networking = {
    # Use NetworkManager for networking
    networkmanager = {
      enable = true;
      # Use NextDNS for my DNS
      insertNameservers = [ "45.90.28.119" "45.90.30.119" ];
      dns = "none";
    };

    dhcpcd.enable = false;

  };

  sound.enable = true;
  hardware = {
    pulseaudio.enable = true;

    # 32 bit sound for steam
    opengl.driSupport32Bit = true;
    pulseaudio.support32Bit = true;
  };

}
