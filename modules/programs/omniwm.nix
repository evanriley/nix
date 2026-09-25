{
  flake.modules.homeManager.omniwm =
    { config, pkgs, ... }:
    {
      home.packages = [ pkgs.omniwm ];
      # OmniWM writes Settings changes through the link into the repo.
      dotfiles.config = [ "omniwm/settings.toml" ];

      launchd.agents.omniwm = {
        enable = true;
        config = {
          # The Home Manager Apps copy keeps a stable path; running the store app would
          # register a second OmniWM with Launch Services on every update.
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
      terminal = pkgs.writeShellScript "new-terminal" ''
        exec /usr/bin/osascript \
          -e 'if application "Ghostty" is running then' \
          -e 'tell application "Ghostty" to new window' \
          -e 'end if' \
          -e 'tell application "Ghostty" to activate'
      '';
    in
    {
      services.skhd = {
        enable = true;
        skhdConfig = ''
          alt - return : ${terminal}
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
