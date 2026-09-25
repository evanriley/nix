{ config, inputs, ... }:
let
  inherit (config.meta) user;
  devices = {
    cinderace.id = "FBEDWXO-5RKRXQM-X7UBGPV-K4CBHTF-W7T7PM4-PZF3P57-RJAR4CX-UUAASAB";
    ninetales.id = "NHA632C-HULI6WD-PLTGJ3L-DFKQIPD-2AWJICR-K3SV7ZA-KMM47CK-LN6VGAL";
    iPad.id = "DXC5NZS-75FMHF2-67UFBCN-6DXVDTW-WUBPDGC-MQHVY4Z-WSEAKNR-WAQVNAP";
    phone = {
      id = "NSIZV2R-QD5IH2J-DQKYMYA-J7ER6FY-56AFI5Y-NTVEZ7T-DD5UCK2-GR47AQ4";
      introducer = true;
    };
  };
  settings = home: {
    inherit devices;
    folders.cloud = {
      label = "Cloud";
      path = "${home}/sync";
      devices = builtins.attrNames devices;
    };
    options.urAccepted = -1;
  };
in
{
  flake.modules.nixos.syncthing =
    { config, ... }:
    let
      home = "/home/${user.name}";
    in
    {
      age.secrets = {
        syncthing-cert = {
          file = inputs.self + "/secrets/${config.networking.hostName}/syncthing-cert.age";
          owner = user.name;
        };
        syncthing-key = {
          file = inputs.self + "/secrets/${config.networking.hostName}/syncthing-key.age";
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
        settings = settings home;
      };
    };

  # For hosts without a NixOS system (macOS): runs as a user agent.
  flake.modules.homeManager.syncthing =
    { config, ... }:
    {
      services.syncthing = {
        enable = true;
        overrideDevices = true;
        overrideFolders = true;
        settings = settings config.home.homeDirectory;
      };
    };
}
