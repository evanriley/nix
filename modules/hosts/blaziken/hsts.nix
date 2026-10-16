{
  flake.modules.nixos.blaziken =
    { lib, ... }:
    {
      options.services.nginx.virtualHosts = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { config, ... }:
            {
              config.extraConfig = lib.mkIf (config.forceSSL || config.addSSL || config.onlySSL) ''
                add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
              '';
            }
          )
        );
      };
    };
}
