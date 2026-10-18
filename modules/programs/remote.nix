{ config, ... }:
let
  inherit (config.meta) user hostKeys;
in
{
  flake.modules.nixos.remote =
    { config, pkgs, ... }:
    {
      services.openssh = {
        enable = true;
        openFirewall = false;
        hostKeys = [
          {
            type = "ed25519";
            path = "/etc/ssh/ssh_host_ed25519_key";
          }
        ];
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
      };

      users.users.${user.name}.openssh.authorizedKeys.keys = user.sshKeys;

      services.tailscale.extraSetFlags = [ "--ssh=false" ];

      services.eternal-terminal.enable = true;

      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
        22
        config.services.eternal-terminal.port
      ];

      environment.systemPackages = [ pkgs.ghostty.terminfo ];
    };

  flake.modules.homeManager.remote =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.eternal-terminal ];

      programs.ssh.settings.cinderace = {
        ControlMaster = "auto";
        ControlPath = "~/.ssh/control-%C";
        ControlPersist = "10m";
      };
    };

  flake.modules.darwin.remote = {
    programs.ssh.knownHosts.cinderace = {
      hostNames = [
        "cinderace"
        "100.91.53.22"
      ];
      publicKey = hostKeys.cinderace;
    };
  };
}
