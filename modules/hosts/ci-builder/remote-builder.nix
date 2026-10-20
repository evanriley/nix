{ config, inputs, ... }:
let
  nixos = config.flake.modules.nixos;
in
{
  meta.ciRemoteBuilderStartupScript = builtins.path {
    path = ./remote-builder-startup-script.sh;
    name = "ci-remote-builder-startup-script.sh";
  };

  flake.nixosConfigurations.ci-remote-builder = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      nixos.ci-builder-image
      nixos.ci-remote-builder
    ];
  };

  flake.modules.nixos.ci-remote-builder =
    { config, lib, ... }:
    let
      user = "builder";
      nixDaemonStdio = "${lib.getExe' config.nix.package "nix-daemon"} --stdio";
    in
    {
      imports = [ nixos.ci-builder-base ];

      options.ciBuilder.remoteBuilderAuthorizedKey = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWJzNr6cFJtfAMNsmAB+uqqTVJuzZ8sInSzBtmJoAyf ci-remote-builder";
        description = "Public key that may log in as ${user}, restricted to running nix-daemon --stdio.";
      };

      config = {
        services.openssh = {
          enable = true;
          ports = [ 22 ];
          openFirewall = true;
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
            AllowUsers = [ user ];
          };
        };

        users.users.${user} = {
          isSystemUser = true;
          group = user;
          useDefaultShell = true;
          openssh.authorizedKeys.keys = [
            ''restrict,command="${nixDaemonStdio}" ${config.ciBuilder.remoteBuilderAuthorizedKey}''
          ];
        };
        users.groups.${user} = { };

        ciBuilder.metadataBlockedUsers = [ user ];

        nix.settings.trusted-users = [ user ];
      };
    };
}
