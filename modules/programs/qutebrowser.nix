{
  flake.modules.homeManager.qutebrowser =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) isDarwin;

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
              lib.makeBinPath ([ pkgs.rbw ] ++ lib.optional (!isDarwin) pkgs.wtype)
            }
            wrapProgram $out/qute-bitwarden --prefix PATH : ${
              lib.makeBinPath [ (if isDarwin then pkgs.choose-gui else pkgs.fuzzel) ]
            }
            wrapProgram $out/qute-cleanurl --prefix PATH : ${
              lib.makeBinPath [
                (if isDarwin then pkgs.writeShellScriptBin "wl-copy" "exec /usr/bin/pbcopy" else pkgs.wl-clipboard)
              ]
            }
            wrapProgram $out/qute-mpv --prefix PATH : ${lib.makeBinPath [ config.programs.mpv.finalPackage ]}
          '';

      dictionary = pkgs.hunspellDictsChromium.en_US;

      dataFiles = {
        "qutebrowser/greasemonkey".source = greasemonkey;
        "qutebrowser/userscripts".source = userscripts;
        "qutebrowser/qtwebengine_dictionaries/${dictionary.dictFileName}".source = dictionary;
      };
    in
    lib.mkMerge [
      { home.packages = [ pkgs.qutebrowser ]; }
      (lib.mkIf (!isDarwin) {
        dotfiles.config = [ "qutebrowser" ];
        xdg.dataFile = dataFiles;
      })
      # qutebrowser reads config.py from ~/.qutebrowser and data from Application Support on macOS.
      (lib.mkIf isDarwin {
        home.file = {
          ".qutebrowser".source = config.dotfiles.link "config/qutebrowser";
        }
        // lib.mapAttrs' (
          name: value: lib.nameValuePair "Library/Application Support/${name}" value
        ) dataFiles;
      })
    ];
}
