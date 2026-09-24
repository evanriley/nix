{ inputs, ... }:
{
  flake.modules.nixos.secrets = {
    imports = [ inputs.agenix.nixosModules.default ];

    # sshd is not enabled, so agenix cannot derive this from its host keys.
    age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };
}
