# agenix recipients. Only public keys belong here.
let
  yubikey-primary = "age1yubikey1-REPLACE-20477902";
  yubikey-backup = "age1yubikey1-REPLACE-20477782";
  paper = "age1-REPLACE-paper";
  admins = [
    yubikey-primary
    yubikey-backup
    paper
  ];

  # /etc/ssh/ssh_host_ed25519_key.pub of each host.
  hosts = {
    cinderace = "ssh-ed25519 REPLACE root@cinderace";
  };

  shared = names: {
    ${names} = {
      publicKeys = admins ++ builtins.attrValues hosts;
    };
  };

  hostSecrets =
    host: names:
    builtins.listToAttrs (
      map (name: {
        name = "${host}/${name}";
        value.publicKeys = admins ++ [ hosts.${host} ];
      }) names
    );
in
shared "evan-password.age"
// shared "listenbrainz-token.age"
// hostSecrets "cinderace" [
  "u2f-mappings.age"
  "borg-passphrase.age"
  "borg-ssh-key.age"
  "syncthing-cert.age"
  "syncthing-key.age"
  "lidarr.env.age"
  "slskd.env.age"
  "soularr-config.age"
]
