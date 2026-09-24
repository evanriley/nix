{ config, inputs, ... }:
let
  inherit (config.meta) user;
in
{
  flake.modules.nixos.users =
    { config, ... }:
    {
      users.mutableUsers = false;

      users.groups.${user.name}.gid = 1000;
      users.users.${user.name} = {
        uid = 1000;
        group = user.name;
        isNormalUser = true;
        description = user.fullName;
        extraGroups = [
          "wheel"
          "networkmanager"
          "video"
          "input"
        ];
        hashedPasswordFile = config.age.secrets.user-password.path;
      };

      age.secrets.user-password.file = inputs.self + "/secrets/evan-password.age";
    };
}
