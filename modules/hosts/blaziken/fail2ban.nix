{ ... }:
{
  flake.modules.nixos.blaziken = {
    services.fail2ban = {
      enable = true;
      maxretry = 5;
      bantime = "1h";
      ignoreIP = [ "100.64.0.0/10" ];
      jails = {
        DEFAULT.settings.findtime = "10m";
        dovecot.settings = {
          enabled = true;
          filter = "dovecot[mode=normal]";
          port = "993,4190";
        };
        postfix.settings = {
          enabled = true;
          filter = "postfix[mode=auth]";
          port = "25,465";
        };
        roundcube-auth.settings = {
          enabled = true;
          port = "80,443";
        };
        kosync = {
          settings = {
            enabled = true;
            port = "80,443";
          };
          filter.Definition = {
            journalmatch = "SYSLOG_IDENTIFIER=nginx_kosync";
            failregex = ''
              ^<HOST> 401 "(?!-")[^"]+"
                ^<HOST> 401 "-" "POST /auth/login-kosync"'';
          };
        };
      };
    };
  };
}
