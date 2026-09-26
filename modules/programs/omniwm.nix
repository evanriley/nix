{ config, ... }:
let
  inherit (config.flake.lib) mkScript;
in
{
  flake.modules.homeManager.omniwm =
    { config, pkgs, ... }:
    {
      home.packages = [ pkgs.omniwm ];
      dotfiles.config = [ "omniwm/settings.toml" ];

      launchd.agents.omniwm = {
        enable = true;
        config = {
          ProgramArguments = [
            "${config.home.homeDirectory}/Applications/Home Manager Apps/OmniWM.app/Contents/MacOS/OmniWM"
          ];
          RunAtLoad = true;
          KeepAlive.SuccessfulExit = false;
          ProcessType = "Interactive";
        };
      };
    };

  flake.modules.darwin.omniwm =
    { lib, pkgs, ... }:
    let
      omniwmctl = "${lib.getBin pkgs.omniwm}/bin/omniwmctl command";
      terminal = mkScript pkgs {
        name = "new-terminal";
        src = ./_omniwm/new-terminal;
      };
    in
    {
      services.skhd = {
        enable = true;
        skhdConfig = ''
          alt - return : ${lib.getExe terminal}
          alt - e : /usr/bin/open "$HOME"
          alt - 0x21 : ${omniwmctl} consume-or-expel-window-left
          alt - 0x1E : ${omniwmctl} consume-or-expel-window-right
          alt - pagedown : ${omniwmctl} switch-workspace next
          alt - pageup : ${omniwmctl} switch-workspace prev
          alt + shift - pagedown : ${omniwmctl} move-column-to-workspace down
          alt + shift - pageup : ${omniwmctl} move-column-to-workspace up
          alt + shift - 0x2C : ${omniwmctl} open-command-palette
        '';
      };
    };
}
