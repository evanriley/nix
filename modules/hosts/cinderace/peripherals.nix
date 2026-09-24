{
  flake.modules.nixos.cinderace =
    { pkgs, ... }:
    {
      services.udev.packages = [
        pkgs.wooting-udev-rules
        # ATK/Compx mice and receivers (WebHID configurator); product IDs vary by mode.
        # uaccess only takes effect in rules sorted before 73-seat-late.rules.
        (pkgs.writeTextDir "lib/udev/rules.d/70-atk.rules" ''
          SUBSYSTEM=="hidraw", ATTRS{idVendor}=="373b", MODE:="0660", TAG+="uaccess"
        '')
      ];
    };
}
