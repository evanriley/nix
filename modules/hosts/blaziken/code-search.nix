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
          User = "zoekt-index";
          Group = "zoekt";
          SupplementaryGroups = [ "gerrit" ];
          Type = "oneshot";
          StateDirectory = "zoekt";
          StateDirectoryMode = "0750";
          UMask = "0027";
          TemporaryFileSystem = [ "/var/lib/gerrit:ro" ];
          BindReadOnlyPaths = [ origin ];
          PrivateNetwork = true;
          NoNewPrivileges = true;
          CapabilityBoundingSet = "";
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [ "AF_UNIX" ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "~@privileged @resources"
          ];
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
          User = "zoekt";
          Group = "zoekt";
          ExecStart = "${pkgs.zoekt}/bin/zoekt-webserver -index ${indexDir} -listen ${listenAddress}";
          Restart = "always";
          UMask = "0077";
          PrivateUsers = true;
          NoNewPrivileges = true;
          CapabilityBoundingSet = "";
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "~@privileged @resources"
          ];
          IPAddressDeny = "any";
          IPAddressAllow = "localhost";
        };
      };

      users.users.zoekt-index = {
        isSystemUser = true;
        group = "zoekt";
      };
      users.users.zoekt = {
        isSystemUser = true;
        group = "zoekt";
      };
      users.groups.zoekt = { };

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
