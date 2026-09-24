{ config, inputs, ... }:
let
  inherit (config.meta) user;
  home = "/home/${user.name}";
in
{
  flake.modules.nixos.syncthing =
    { config, ... }:
    {
      age.secrets = {
        syncthing-cert = {
          file = inputs.self + "/secrets/syncthing-cert.age";
          owner = user.name;
        };
        syncthing-key = {
          file = inputs.self + "/secrets/syncthing-key.age";
          owner = user.name;
        };
      };

      services.syncthing = {
        enable = true;
        user = user.name;
        group = user.name;
        dataDir = home;
        configDir = "${home}/.local/state/syncthing";
        cert = config.age.secrets.syncthing-cert.path;
        key = config.age.secrets.syncthing-key.path;
        openDefaultPorts = true;
        overrideDevices = true;
        overrideFolders = true;
        settings = {
          devices = {
            ninetales.id = "AQYX6BX-U36AVLK-S7H52BJ-QR4QBFG-TGF6YVC-TAQCTN4-AL6D66X-DPE7XQZ";
            iPad.id = "DXC5NZS-75FMHF2-67UFBCN-6DXVDTW-WUBPDGC-MQHVY4Z-WSEAKNR-WAQVNAP";
            phone = {
              id = "NSIZV2R-QD5IH2J-DQKYMYA-J7ER6FY-56AFI5Y-NTVEZ7T-DD5UCK2-GR47AQ4";
              introducer = true;
            };
          };
          folders.cloud = {
            label = "Cloud";
            path = "${home}/sync";
            devices = [
              "ninetales"
              "iPad"
              "phone"
            ];
          };
          options.urAccepted = -1;
        };
      };
    };
}
