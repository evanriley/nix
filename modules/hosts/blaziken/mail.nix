{ config, inputs, ... }:
let
  inherit (config.meta) domain user;
in
{
  flake.modules.nixos.blaziken =
    { ... }:
    {
      imports = [ inputs.nixos-mailserver.nixosModules.default ];

      mailserver = {
        enable = true;
        stateVersion = 5;
        fqdn = "mail.${domain}";
        domains = [ domain ];
        x509.useACMEHost = domain;
        enableImapSsl = false;
        enableSubmissionSsl = false;
        srs.enable = true;
        forwards = {
          "postmaster@${domain}" = user.email;
          "abuse@${domain}" = user.email;
          "gerrit@${domain}" = user.email;
        };
      };

      users.users.postfix.extraGroups = [ "nginx" ];
      users.users.dovecot2.extraGroups = [ "nginx" ];
    };
}
