{
  flake.modules.nixos.cinderace =
    { pkgs, ... }:
    {
      services.udev.packages = [ pkgs.wooting-udev-rules ];

      services.udev.extraRules = ''
        # Fractal Scape headset (ScapeCtl).
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="36bc", ATTRS{idProduct}=="0001", TAG+="uaccess"
        # ATK/Compx mice and receivers; product IDs vary by mode.
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="373b", MODE:="0660", TAG+="uaccess"
      '';
    };
}
