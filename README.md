# nix

My NixOS config files.

# Building

configuration.nix is left empty except for:

```
{

  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      /home/evan/nix/modules/hosts/zeus.nix
    ];
}

```

Currently this requires both of these channels

```
nixos nixos https://nixos.org/channels/nixos-20.03
nixos-unstable nixos-unstable https://nixos.org/channels/nixos-unstable
```

# other dotfiles

While I still figure out Nix/NixOS I'm still also using my past dotfiles here:
[dotfiles](https://github.com/evanriley/dotfiles)
