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
        ];
        hashedPasswordFile = config.age.secrets.user-password.path;
      };

      age.secrets.user-password.file = inputs.self + "/secrets/${user.name}-password.age";
    };

  flake.modules.darwin.users = {
    system.primaryUser = user.name;

    # nix-darwin only changes the login shell of users it manages.
    users.knownUsers = [ user.name ];
    users.users.${user.name} = {
      uid = 501;
      home = "/Users/${user.name}";
    };
  };
}
