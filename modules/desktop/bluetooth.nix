{
  flake.modules.nixos.bluetooth = {
    hardware.bluetooth.enable = true;
    services.blueman.enable = true;

    services.borgmatic.configurations.home.source_directories = [ "/var/lib/bluetooth" ];
  };
}
