{ config, ... }:
let
  inherit (config.flake.lib) uaccessRules;
in
{
  flake.modules.nixos.cinderace =
    { pkgs, ... }:
    {
      services.udev.packages = [
        pkgs.wooting-udev-rules
        # ATK/Compx mice and receivers (WebHID configurator); product IDs vary by mode.
        (uaccessRules pkgs "atk" ''
          SUBSYSTEM=="hidraw", ATTRS{idVendor}=="373b", MODE:="0660", TAG+="uaccess"
        '')
      ];
    };
}
