{
  flake.modules.homeManager.music =
    { config, pkgs, ... }:
    let
      home = config.home.homeDirectory;
    in
    {
      home.packages = [
        pkgs.mpd
        pkgs.rmpc
      ];

      systemd.user.services = {
        mpd = {
          Unit = {
            Description = "Music Player Daemon";
            After = [ "network.target" ];
          };
          Service = {
            ExecStart = "${pkgs.mpd}/bin/mpd --no-daemon ${home}/.config/mpd/mpd.conf";
            Restart = "on-failure";
          };
          Install.WantedBy = [ "default.target" ];
        };

        mpd-mpris = {
          Unit = {
            Description = "MPRIS bridge for MPD";
            Requires = [ "mpd.service" ];
            After = [ "mpd.service" ];
          };
          Service = {
            Type = "dbus";
            BusName = "org.mpris.MediaPlayer2.mpd";
            ExecStart = "${pkgs.mpd-mpris}/bin/mpd-mpris -host 127.0.0.1 -no-instance";
            Restart = "on-failure";
          };
          Install.WantedBy = [ "default.target" ];
        };

        listenbrainz-mpd = {
          Unit = {
            Description = "ListenBrainz scrobbler for MPD";
            Requires = [ "mpd.service" ];
            After = [ "mpd.service" ];
            ConditionPathExists = "/run/agenix/listenbrainz-token";
          };
          Service = {
            Type = "notify";
            ExecStart = "${pkgs.listenbrainz-mpd}/bin/listenbrainz-mpd";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
    };
}
