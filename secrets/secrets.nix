# agenix recipients. Only public keys belong here.
let
  yubikey-primary = "age1yubikey1-REPLACE-20477902";
  yubikey-backup = "age1yubikey1-REPLACE-20477782";
  paper = "age1-REPLACE-paper";

  cinderace = "ssh-ed25519 REPLACE root@cinderace";

  admins = [
    yubikey-primary
    yubikey-backup
    paper
  ];
  cinderaceSecret.publicKeys = admins ++ [ cinderace ];
in
{
  "evan-password.age" = cinderaceSecret;
  "u2f-mappings.age" = cinderaceSecret;
  "borg-passphrase.age" = cinderaceSecret;
  "borg-ssh-key.age" = cinderaceSecret;
  "syncthing-cert.age" = cinderaceSecret;
  "syncthing-key.age" = cinderaceSecret;
  "listenbrainz-token.age" = cinderaceSecret;
  "lidarr.env.age" = cinderaceSecret;
  "slskd.env.age" = cinderaceSecret;
  "soularr-config.age" = cinderaceSecret;
}
