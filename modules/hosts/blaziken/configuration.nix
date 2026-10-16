{
  # KS-5 (Xeon E3-1270 v6, 32 GB) at OVH. Boot is UEFI with no IPMI access,
  # so the bootloader installs to the removable fallback path and to both
  # disks' MBR; see disko.nix for the mirrored layout.
  config,
  inputs,
  ...
}:
let
  nixos = config.flake.modules.nixos;

  sda = "/dev/disk/by-id/ata-HGST_HUS724020ALA640_PN2134P6HDTRJP";
  sdb = "/dev/disk/by-id/ata-HGST_HUS724020ALA640_PN1134P6HHXZZN";
in
{
  flake.nixosConfigurations.blaziken = inputs.nixpkgs.lib.nixosSystem {
    modules = [ nixos.blaziken ];
  };

  flake.modules.nixos.blaziken =
    { pkgs, ... }:
    {
      imports = [ nixos.server ];
      networking.hostName = "blaziken";

      system.stateVersion = "26.05";

      nixpkgs.hostPlatform = "x86_64-linux";
      hardware.enableRedistributableFirmware = true;

      boot = {
        kernelPackages = pkgs.linuxPackages_latest;

        swraid = {
          enable = true;
          # mdmonitor exits failed without somewhere to send events.
          mdadmConf = "PROGRAM ${pkgs.coreutils}/bin/true";
        };

        initrd.availableKernelModules = [
          "ahci"
          "xhci_pci"
          "usbhid"
          "usb_storage"
          "sd_mod"
        ];
        kernelModules = [ "kvm-intel" ];

        loader = {
          efi = {
            canTouchEfiVariables = false;
            efiSysMountPoint = "/boot/efi";
          };
          grub = {
            enable = true;
            efiSupport = true;
            efiInstallAsRemovable = true;
            devices = [
              sda
              sdb
            ];
            configurationLimit = 10;
          };
        };
      };

      # The rescue system names the interface eth0; keep that stable.
      networking = {
        useDHCP = false;
        usePredictableInterfaceNames = false;
        nameservers = [
          "9.9.9.9"
          "1.1.1.1"
          "2620:fe::fe"
        ];
        defaultGateway = {
          address = "147.135.1.254";
          interface = "eth0";
        };
        # ssh, http, https, gerrit over ssh
        firewall.allowedTCPPorts = [
          22
          80
          443
          29418
        ];
        interfaces.eth0 = {
          ipv4.addresses = [
            {
              address = "147.135.1.187";
              prefixLength = 24;
            }
          ];
          ipv6.addresses = [
            {
              address = "2604:2dc0:100:bb::1";
              prefixLength = 128;
            }
          ];
          # The /128 leaves the gateway off-link, so the route needs onlink.
          ipv6.routes = [
            {
              address = "::";
              prefixLength = 0;
              via = "2604:2dc0:100:ff:ff:ff:ff:ff";
              options.onlink = "";
            }
          ];
        };
      };

      # deploy-rs activates as root over sudo from evan.
      security.sudo.wheelNeedsPassword = false;

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
      };

      users.users.evan = {
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKvrBtmYXCnEIYTTlf1PjSkwrUU47CeNFEgq4hQ10vWi"
          "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIDUa51ANhGFP945U5rpjwK4q4YSj9v79pcUJkn5zlu5sAAAABHNzaDo= evan@cinderance yubikey-20477782 auth"
          "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIK4PMbMXc6J5Vgah12OYp2jPRhAg47U0xssVS4kTphBAAAAABHNzaDo= evan@cinderance yubikey-20477902 auth"
        ];
      };
    };
}
