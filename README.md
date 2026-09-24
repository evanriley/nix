# nix

NixOS, nix-darwin and home-manager configuration, structured with the
[dendritic pattern](https://github.com/mightyiam/dendritic): every file is a
flake-parts module that configures one feature across NixOS, nix-darwin and
home-manager.

| Host | Platform | Status |
| --- | --- | --- |
| `cinderace` | NixOS, x86_64 desktop | Active |

## Usage

Clone:

```sh
git clone git@github.com:evanriley/nix.git ~/nix
```

The system and the user environment are applied separately. `nh` reads the
flake location from `NH_FLAKE` (`/home/evan/nix`).

Apply the system configuration:

```sh
nh os switch
```

Apply the home configuration (no sudo). It fetches Berkeley Mono from the
private `evanriley/berkeley-mono` repository, which needs GitHub SSH access:

```sh
nh home switch
```

Build without switching:

```sh
nh os build
nh home build
```

Boot the configuration in a VM:

```sh
nix run ~/nix#nixosConfigurations.cinderace.config.system.build.vm
```

Update inputs:

```sh
nix flake update --flake ~/nix
```

Enter the development shell (agenix, age, age-plugin-yubikey, mkpasswd):

```sh
nix develop ~/nix
```

### Dotfiles

Application configuration files are symlinked from this repository into
`~/.config` without going through the Nix store. Edits to them apply
immediately. Adding or removing a linked file requires a rebuild.

### Theme

Colors come from the Monobiome Alpine palette in `modules/theme/palette.nix`.
darkman switches between the dark base generation and the `light`
specialisation at sunrise and sunset. Switch manually with:

```sh
darkman set light
darkman set dark
```

### Secrets

Secrets are encrypted with [agenix](https://github.com/ryantm/agenix). The
recipients for each secret are listed in `secrets/secrets.nix`:

- the host SSH key, used to decrypt at boot
- a PIV identity on each YubiKey, used to edit and rekey
- an offline paper key, for recovery

Edit or create a secret (requires a YubiKey touch):

```sh
cd ~/nix/secrets
agenix -e <name>.age -i ~/.config/age/yubikeys.txt
```

After changing recipients in `secrets/secrets.nix`, rekey every secret:

```sh
cd ~/nix/secrets
agenix -r -i ~/.config/age/yubikeys.txt
```

### Installation

[INSTALL.md](INSTALL.md) covers a full install of `cinderace`.

## Inspiration and resources

- [mightyiam/dendritic](https://github.com/mightyiam/dendritic)
- [NotAShelf/nyx](https://github.com/NotAShelf/nyx)
- [flake-parts](https://flake.parts)
- [vic/import-tree](https://github.com/vic/import-tree)
- [home-manager](https://github.com/nix-community/home-manager)
- [agenix](https://github.com/ryantm/agenix)
- [age-plugin-yubikey](https://github.com/str4d/age-plugin-yubikey)
- [lanzaboote](https://github.com/nix-community/lanzaboote)
