{ config, ... }:
let
  inherit (config.meta) domain mailDomains user;
  primaryDomain = "evanriley.com";
  externalDomains = builtins.filter (d: d != domain) mailDomains;
  autoconfigPaths = [
    "/mail/config-v1.1.xml"
    "/.well-known/autoconfig/mail/config-v1.1.xml"
  ];
in
{
  flake.modules.nixos.blaziken =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.mailserver) fqdn;

      domainElements = lib.concatMapStringsSep "\n" (d: "    <domain>${d}</domain>") mailDomains;

      autoconfig = pkgs.writeText "config-v1.1.xml" ''
        <?xml version="1.0" encoding="UTF-8"?>
        <clientConfig version="1.1">
          <emailProvider id="${primaryDomain}">
        ${domainElements}
            <displayName>${user.fullName} mail</displayName>
            <displayShortName>${user.fullName}</displayShortName>
            <incomingServer type="imap">
              <hostname>${fqdn}</hostname>
              <port>993</port>
              <socketType>SSL</socketType>
              <authentication>password-cleartext</authentication>
              <username>%EMAILADDRESS%</username>
            </incomingServer>
            <outgoingServer type="smtp">
              <hostname>${fqdn}</hostname>
              <port>465</port>
              <socketType>SSL</socketType>
              <authentication>password-cleartext</authentication>
              <username>%EMAILADDRESS%</username>
            </outgoingServer>
          </emailProvider>
        </clientConfig>
      '';

      discoveryLocations = lib.listToAttrs (
        map (
          path:
          lib.nameValuePair "= ${path}" {
            alias = autoconfig;
            extraConfig = "default_type text/xml;";
          }
        ) autoconfigPaths
      );
    in
    {
      services.nginx.virtualHosts = {
        "autoconfig.${domain}" = {
          forceSSL = true;
          useACMEHost = domain;
          locations = discoveryLocations;
        };

        "autoconfig.${primaryDomain}" = {
          forceSSL = true;
          enableACME = true;
          serverAliases = map (d: "autoconfig.${d}") (
            builtins.filter (d: d != primaryDomain) externalDomains
          );
          locations = discoveryLocations;
        };
      };
    };
}
