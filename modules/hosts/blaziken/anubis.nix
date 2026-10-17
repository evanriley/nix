{ config, ... }:
let
  inherit (config.meta) secrets;
in
{
  flake.modules.nixos.blaziken =
    { config, lib, ... }:
    {
      age.secrets.anubis-key.file = secrets + "/blaziken/anubis-key.age";

      services.anubis.defaultOptions.settings.ED25519_PRIVATE_KEY_HEX_FILE = "%d/key";

      systemd.services = lib.mapAttrs' (
        name: _:
        lib.nameValuePair "anubis-${name}" {
          serviceConfig.LoadCredential = "key:${config.age.secrets.anubis-key.path}";
          restartTriggers = [ (builtins.hashFile "sha256" config.age.secrets.anubis-key.file) ];
        }
      ) config.services.anubis.instances;
    };
}
