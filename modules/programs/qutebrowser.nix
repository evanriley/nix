{
  flake.modules.homeManager.qutebrowser =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      sponsorblock = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/afreakk/greasemonkeyscripts/1ab9f20435cdc39c6551e940fb7788d3207161e6/youtube_sponsorblock.js";
        hash = "sha256-2sNlWL0KOAOMe2pllyKVBT4gAICokyDOuHPkVfUrYN4=";
      };
      clearurls = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/ClearURLs/Rules/11086f40512774dcadef54079f1ba023bfacf940/data.min.json";
        hash = "sha256-syjSpblbGyO6wskTQqje7j+aOCallQv54o4zL/2UzS8=";
      };

      greasemonkey = pkgs.runCommand "qutebrowser-greasemonkey" { } ''
        mkdir -p $out
        cp ${./_qutebrowser/greasemonkey}/*.user.js $out/
        cp ${sponsorblock} $out/sponsorblock.user.js
      '';

      userscripts =
        pkgs.runCommand "qutebrowser-userscripts"
          {
            nativeBuildInputs = [ pkgs.makeWrapper ];
            buildInputs = [ pkgs.python3 ];
          }
          ''
            mkdir -p $out
            cp ${./_qutebrowser/userscripts}/* $out/
            chmod +x $out/*
            patchShebangs $out
            cp ${clearurls} $out/clearurls-data.min.json
            wrapProgram $out/qute-bitwarden-local --prefix PATH : ${
              lib.makeBinPath [
                pkgs.rbw
                pkgs.fuzzel
                pkgs.wtype
              ]
            }
            wrapProgram $out/qute-bitwarden-fuzzel --prefix PATH : ${lib.makeBinPath [ pkgs.fuzzel ]}
            wrapProgram $out/qute-cleanurl --prefix PATH : ${lib.makeBinPath [ pkgs.wl-clipboard ]}
            wrapProgram $out/qute-mpv --prefix PATH : ${lib.makeBinPath [ config.programs.mpv.finalPackage ]}
          '';
    in
    {
      dotfiles.config = [ "qutebrowser" ];
      home.packages = [ pkgs.qutebrowser ];

      xdg.dataFile = {
        "qutebrowser/greasemonkey".source = greasemonkey;
        "qutebrowser/userscripts".source = userscripts;
      };
    };
}
