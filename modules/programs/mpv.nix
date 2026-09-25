{
  flake.modules.homeManager.mpv =
    { pkgs, ... }:
    {
      dotfiles.config = [ "mpv" ];

      programs.mpv = {
        enable = true;
        package = pkgs.mpv.override {
          scripts = with pkgs.mpvScripts; [
            modernx
            thumbfast
            sponsorblock
          ];
        };
      };

      home.packages = [
        # Font for the modernx OSC.
        pkgs.mpvScripts.modernx
        pkgs.yt-dlp
      ];
    };
}
