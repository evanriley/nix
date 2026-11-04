{ config, inputs, ... }:
let
  inherit (config.meta)
    domain
    user
    secrets
    ;
  domains = config.meta.mailDomains;
in
{
  flake.modules.nixos.blaziken =
    { config, ... }:
    {
      imports = [ inputs.nixos-mailserver.nixosModules.default ];

      age.secrets.mail-evan-hash.file = secrets + "/blaziken/mail-evan-hash.age";

      systemd.services.dovecot.restartTriggers = [
        (builtins.hashFile "sha256" config.age.secrets.mail-evan-hash.file)
      ];

      mailserver = {
        enable = true;
        stateVersion = 5;
        fqdn = "mail.${domain}";
        inherit domains;
        x509.useACMEHost = domain;
        enableManageSieve = true;
        srs.enable = true;
        messageSizeLimit = 50 * 1024 * 1024;
        indexDir = "/var/lib/dovecot/indices";
        fullTextSearch.enable = true;
        mailboxes = {
          Trash = {
            auto = "no";
            special_use = "\\Trash";
            fts_autoindex = false;
            autoexpunge = "30d";
          };
          Junk = {
            auto = "subscribe";
            special_use = "\\Junk";
            fts_autoindex = false;
            autoexpunge = "30d";
          };
          Drafts = {
            auto = "subscribe";
            special_use = "\\Drafts";
          };
          Sent = {
            auto = "subscribe";
            special_use = "\\Sent";
          };
          Archive = {
            auto = "subscribe";
            special_use = "\\Archive";
          };
        };
        accounts."${user.email}" = {
          hashedPasswordFile = config.age.secrets.mail-evan-hash.path;
          aliases = map (d: "@${d}") domains;
        };
        forwards = {
          "postmaster@${domain}" = user.email;
          "abuse@${domain}" = user.email;
          "gerrit@${domain}" = user.email;
          "news@${domain}" = user.email;
        };
      };

      services.rspamd.locals."settings.conf".text = ''
        loopback {
          priority = high;
          ip = [ "127.0.0.1", "::1" ];
          apply {
            actions {
              reject = null;
              "add header" = null;
              "rewrite subject" = null;
              greylist = null;
            }
          }
        }
      '';

      services.kresd.extraConfig = ''
        policy.add(policy.suffix(policy.STUB('100.100.100.100'), { todname('ts.net.') }))
      '';

      users.users.postfix.extraGroups = [ "nginx" ];
      users.users.dovecot2.extraGroups = [ "nginx" ];
    };
}
