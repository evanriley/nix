{ inputs, ... }:
{
  flake.modules.nixos.yubikey =
    { config, pkgs, ... }:
    {
      services.pcscd.enable = true;
      services.udev.packages = [
        pkgs.yubikey-personalization
        pkgs.libfido2
      ];

      environment.systemPackages = with pkgs; [
        yubikey-manager
        yubikey-personalization
        libfido2
        age-plugin-yubikey
      ];

      age.secrets.u2f-mappings = {
        file = inputs.self + "/secrets/u2f-mappings.age";
        mode = "0444";
      };

      security.pam.u2f = {
        control = "sufficient";
        settings = {
          authfile = config.age.secrets.u2f-mappings.path;
          cue = true;
          userpresence = 1;
          pinverification = 0;
          userverification = 0;
        };
      };
      # Not on login: GDM's password unlocks the GNOME keyring.
      security.pam.services = {
        sudo.u2fAuth = true;
        swaylock.u2fAuth = true;
      };
    };
}
