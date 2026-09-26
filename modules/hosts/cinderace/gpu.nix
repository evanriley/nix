{
  flake.modules.nixos.cinderace = {
    services.lact.enable = true;
    # Unlocks voltage offsets and power limits in LACT.
    hardware.amdgpu.overdrive.enable = true;

    # Written by the LACT GUI.
    services.borgmatic.configurations.home.source_directories = [ "/etc/lact" ];
  };
}
