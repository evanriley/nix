# agenix recipients. Only public keys belong here.
let
  yubikey-primary = "age1yubikey1qtd2ghr0jy6k32srxygw4wf83dggd8zzuvywqq56f47gfdnp0ut26lhjj27";
  yubikey-backup = "age1yubikey1qv98gry9ya6gj4tg4py8adrcl6z65te7kdy2a75cs7369t7lj407sv4ayc5";
  paper = "age1e7g7h7aceg5x49cchvuzcjs8n4ey5dgemtgymx40r2te7xl00q8s03902n";
  admins = [
    yubikey-primary
    yubikey-backup
    paper
  ];

  # /etc/ssh/ssh_host_ed25519_key.pub of each host.
  hosts = {
    cinderace = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIDES4qGRr0cZtmy1BQ0aO+5Ti1O+7Pyzk7O6XJnfuAI root@cinderace";
    ninetales = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINCffWfU8zD0rbzO2bcefQZf0uQ7meUM+jVA+OuB88J4";
  };

  shared = hostNames: name: {
    ${name}.publicKeys = admins ++ map (host: hosts.${host}) hostNames;
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
shared [ "cinderace" ] "evan-password.age"
// shared [ "cinderace" ] "listenbrainz-token.age"
// shared [ "cinderace" "ninetales" ] "nextdns.conf.age"
// shared [ "cinderace" "ninetales" ] "atuin-key.age"
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
// hostSecrets "ninetales" [
  "borg-passphrase.age"
  "borg-ssh-key.age"
]
