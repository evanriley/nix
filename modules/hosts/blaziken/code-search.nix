{
  config,
  ...
}:
let
  inherit (config.meta) domain;
  origin = "/var/lib/gerrit/git/maybe.git";
  stateDir = "/var/lib/zoekt";
  clone = "${stateDir}/maybe.git";
  indexDir = "${stateDir}/index";
  listenAddress = "127.0.0.1:6070";
in
{
  flake.modules.nixos.blaziken =
    { pkgs, ... }:
    let
      zigCtagsOptions = pkgs.writeText "zig.ctags" ''
        --langdef=Zig
        --map-Zig=+.zig
        --kinddef-Zig=f,function,functions
        --kinddef-Zig=c,constant,constants
        --kinddef-Zig=v,variable,variables
        --regex-Zig=/^[ \t]*(pub[ \t]+)?((export|extern([ \t]+"[^"]*")?|inline|noinline)[ \t]+)?fn[ \t]+([A-Za-z_][A-Za-z0-9_]*)/\5/f/
        --regex-Zig=/^(pub[ \t]+)?((export|extern([ \t]+"[^"]*")?)[ \t]+)?const[ \t]+([A-Za-z_][A-Za-z0-9_]*)/\5/c/
        --regex-Zig=/^[ \t]+pub[ \t]+const[ \t]+([A-Za-z_][A-Za-z0-9_]*)/\1/c/
        --regex-Zig=/^(pub[ \t]+)?((export|extern([ \t]+"[^"]*")?)[ \t]+)?(threadlocal[ \t]+)?var[ \t]+([A-Za-z_][A-Za-z0-9_]*)/\6/v/
        --regex-Zig=/^[ \t]+pub[ \t]+var[ \t]+([A-Za-z_][A-Za-z0-9_]*)/\1/v/
      '';
      # universal-ctags has no Zig parser and go-ctags passes a fixed --languages
      # list, so the Zig definition must come after zoekt's arguments.
      ctags = pkgs.writeShellScript "universal-ctags" ''
        exec ${pkgs.universal-ctags}/bin/universal-ctags "$@" --options=${zigCtagsOptions} --languages=+Zig
      '';
    in
    {
      systemd.services.zoekt-index = {
        description = "Index the monorepo for code search";
        path = [ pkgs.git ];
        environment.CTAGS_COMMAND = "${ctags}";
        serviceConfig = {
          User = "gerrit";
          Group = "gerrit";
          Type = "oneshot";
          StateDirectory = "zoekt";
        };
        # zoekt reads repositories with go-git, which cannot read the packs
        # Gerrit's JGit writes, so it indexes a copy written by C git.
        script = ''
          if [ ! -d ${clone} ]; then
            rm -rf ${clone}.new
            git clone --quiet --bare --no-local ${origin} ${clone}.new
            mv ${clone}.new ${clone}
          fi
          git -C ${clone} config zoekt.name maybe
          git -C ${clone} config zoekt.web-url https://code.${domain}/maybe.git
          git -C ${clone} config zoekt.web-url-type cgit
          git -C ${clone} fetch --quiet --prune origin '+refs/heads/*:refs/heads/*'
          ${pkgs.zoekt}/bin/zoekt-git-index -require_ctags -branches main -index ${indexDir} ${clone}
        '';
      };

      systemd.timers.zoekt-index = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitActiveSec = "5min";
          Unit = "zoekt-index.service";
        };
      };

      systemd.services.zoekt-webserver = {
        description = "zoekt code search web server";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "gerrit";
          Group = "gerrit";
          StateDirectory = "zoekt";
          ExecStart = "${pkgs.zoekt}/bin/zoekt-webserver -index ${indexDir} -listen ${listenAddress}";
          Restart = "always";
        };
      };

      services.anubis.instances.search = {
        group = "nginx";
        settings.TARGET = "http://${listenAddress}";
      };

      services.nginx.virtualHosts."cs.${domain}" = {
        forceSSL = true;
        useACMEHost = domain;
        locations."/".proxyPass = "http://unix:/run/anubis/anubis-search/anubis.sock";
      };
    };
}
