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
}
