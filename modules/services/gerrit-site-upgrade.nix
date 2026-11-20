{
  flake.modules.nixos.gerrit-site-upgrade =
    { config, lib, ... }:
    let
      inherit (config.services.gerrit) package;
    in
    {
      systemd.services.gerrit.preStart = lib.mkMerge [
        (lib.mkBefore ''
          service_umask="$(umask)"
        '')
        (lib.mkAfter ''
          site_package=.nixos-gerrit-package
          if [[ ! -e "$site_package" || "$(< "$site_package")" != "${package}" ]]; then
            gerrit_config="$(readlink etc/gerrit.config)"
            replication_config="$(readlink etc/replication.config)"
            (
              umask "$service_umask"
              gerrit init --batch --no-auto-start --skip-plugins
            )
            ln -sfv "$gerrit_config" etc/gerrit.config
            ln -sfv "$replication_config" etc/replication.config
            printf '%s\n' "${package}" > "$site_package.tmp"
            mv "$site_package.tmp" "$site_package"
          fi
        '')
      ];
    };
}
