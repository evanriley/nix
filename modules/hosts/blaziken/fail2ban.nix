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
          filter = {
            INCLUDES.before = "common.conf";
            Definition = {
              _daemon = "nginx_kosync";
              journalmatch = "SYSLOG_IDENTIFIER=nginx_kosync";
              failregex = ''
                ^%(__prefix_line)s<HOST> 401 "(?!-")[^"]+"
                  ^%(__prefix_line)s<HOST> 401 "-" "POST /auth/login-kosync"'';
            };
          };
        };
      };
    };
  };
}
