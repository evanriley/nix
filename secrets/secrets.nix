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
    blaziken = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMltQu8qZLDlna9ZoESX8WJEi7Gv+43JDwq59E3LZUmz root@blaziken";
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

  mirrorKeys = map (project: "${project.name}-mirror-key.age") (
    builtins.filter (project: project ? mirror) (
      builtins.fromJSON (builtins.readFile ../../projects.json)
    )
  );
in
shared [ "cinderace" "blaziken" ] "evan-password.age"
// shared [ "cinderace" ] "listenbrainz-token.age"
// shared [ "cinderace" "ninetales" ] "nextdns.conf.age"
// shared [ "cinderace" "ninetales" ] "fastmail-mail.age"
// shared [ "cinderace" "ninetales" ] "fastmail-authinfo.age"
// shared (builtins.attrNames hosts) "atuin-key.age"
// shared (builtins.attrNames hosts) "openrouter-key.age"
// shared (builtins.attrNames hosts) "kagi-key.age"
// shared (builtins.attrNames hosts) "coralbricks-key.age"
// shared (builtins.attrNames hosts) "context7-key.age"
// shared (builtins.attrNames hosts) "anthropic-key.age"
// shared [ "cinderace" "ninetales" ] "eca-netrc.age"
// hostSecrets "cinderace" [
  "u2f-mappings.age"
  "borg-passphrase.age"
  "borg-ssh-key.age"
  "syncthing-cert.age"
  "syncthing-key.age"
  "fastmail-caldav.age"
  "lidarr.env.age"
  "slskd.env.age"
  "soularr-config.age"
]
// hostSecrets "blaziken" [
  "cloudflare-dns.age"
  "buildkite-token.age"
  "cachix-token.age"
  "buildkite-rest-token.age"
  "gerrit-ci-key.age"
  "orca-cachix-token.age"
  "gcp-ci-key.age"
  "ci-cache-writer.age"
  "ci-cache-reader.age"
  "ci-cache-signing-key.age"
  "borg-ssh-key.age"
  "borg-passphrase.age"
  "healthchecks-ping.age"
  "healthchecks-heartbeat.age"
  "healthchecks-disks.age"
  "anubis-key.age"
  "pocket-id-key.age"
  "gerrit-oidc-secret.age"
  "git-bug-oidc-secret.age"
  "oauth2-proxy-cookie-secret.age"
]
// hostSecrets "blaziken" mirrorKeys
// hostSecrets "ninetales" [
  "borg-passphrase.age"
  "borg-ssh-key.age"
]
