{ config, inputs, ... }:
let
  inherit (config.meta) user;
in
{
  flake.modules.nixos.users =
    { config, pkgs, ... }:
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
          "video"
        ];
        hashedPasswordFile = config.age.secrets.user-password.path;
      };

      age.secrets.user-password.file = inputs.self + "/secrets/${user.name}-password.age";

      # AccountsService has no declarative config, and its users file also holds
      # the last GDM session, so only the Icon= line is managed.
      system.activationScripts.avatar = ''
        icon=/var/lib/AccountsService/icons/${user.name}
        usersFile=/var/lib/AccountsService/users/${user.name}
        changed=

        install -d -m 0775 /var/lib/AccountsService/icons
        install -d -m 0700 /var/lib/AccountsService/users
        if ! ${pkgs.diffutils}/bin/cmp -s ${./avatar.jpg} "$icon"; then
          install -m 0644 ${./avatar.jpg} "$icon"
          changed=1
        fi

        if [ ! -e "$usersFile" ] || ! grep -qx '\[User\]' "$usersFile"; then
          printf '[User]\nIcon=%s\n' "$icon" >> "$usersFile"
          chmod 0600 "$usersFile"
          changed=1
        elif ! grep -qx "Icon=$icon" "$usersFile"; then
          if grep -q '^Icon=' "$usersFile"; then
            ${pkgs.gnused}/bin/sed -i "s|^Icon=.*|Icon=$icon|" "$usersFile"
          else
            ${pkgs.gnused}/bin/sed -i "/^\[User\]$/a Icon=$icon" "$usersFile"
          fi
          changed=1
        fi

        # accounts-daemon caches users; skip at boot, where systemd is not up yet.
        if [ -n "$changed" ] && [ -d /run/systemd/system ]; then
          ${config.systemd.package}/bin/systemctl try-restart --no-block accounts-daemon.service
        fi
      '';
    };

  flake.modules.darwin.users = {
    system.primaryUser = user.name;

    # nix-darwin only changes the login shell of users it manages.
    users.knownUsers = [ user.name ];
    users.users.${user.name} = {
      uid = 501;
      home = "/Users/${user.name}";
    };

    system.activationScripts.postActivation.text = ''
      if dscl . -read /Users/${user.name} dsAttrTypeNative:AvatarRepresentation >/dev/null 2>&1; then
        dscl . -delete /Users/${user.name} dsAttrTypeNative:AvatarRepresentation
      fi
      picture="/Library/User Pictures/${user.name}.jpg"
      if ! cmp -s ${./avatar.jpg} "$picture"; then
        install -m 0644 ${./avatar.jpg} "$picture"
      fi
      # dscl prints values containing spaces on their own indented line.
      if [ "$(dscl . -read /Users/${user.name} Picture 2>/dev/null | tail -n +2 | sed 's/^ *//')" != "$picture" ]; then
        dscl . -create /Users/${user.name} Picture "$picture"
      fi
      if [ "$(dscl . -read /Users/${user.name} JPEGPhoto 2>/dev/null | tail -n +2 | tr -d ' \n')" \
        != "$(xxd -p ${./avatar.jpg} | tr -d '\n')" ]; then
        dscl . -delete /Users/${user.name} JPEGPhoto 2>/dev/null || true
        records=$(mktemp)
        printf '0x0A 0x5C 0x3A 0x2C dsRecTypeStandard:Users 2 dsAttrTypeStandard:RecordName externalbinary:dsAttrTypeStandard:JPEGPhoto\n%s:%s\n' \
          ${user.name} ${./avatar.jpg} > "$records"
        dsimport "$records" /Local/Default M
        rm -f "$records"
      fi
    '';
  };
}
