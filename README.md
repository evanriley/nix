# nix

| Host | Hardware | System | Status |
| --- | --- | --- | --- |
| `cinderace` | Desktop: Ryzen 7 9800X3D, Radeon RX 9070 XT | NixOS, x86_64-linux | Active |
| `ninetales` | MacBook Pro, M1 Pro | nix-darwin, aarch64-darwin | Active |

## Usage

Clone to `~/nix`, where `nh` expects the flake (`NH_FLAKE`):

```sh
git clone git@github.com:evanriley/nix.git ~/nix
```

The system and the home configuration are applied separately:

| | cinderace | ninetales |
| --- | --- | --- |
| System | `nh os switch` | `nh darwin switch` |
| Home | `nh home switch` | `nh home switch` |
| Build only | `nh os build`, `nh home build` | `nh darwin build`, `nh home build` |

The home configuration fetches Berkeley Mono from the private
`evanriley/berkeley-mono` repository, so it needs GitHub SSH access.

Update inputs:

```sh
nix flake update --flake ~/nix
```

Start a project from a template (`rust`, `zig`, `ocaml`, `gleam`, `python`,
`clojure`):

```sh
nix flake init -t ~/nix#<template>
```

The theme follows darkman on cinderace and the system appearance on
ninetales. To switch cinderace manually:

```sh
darkman set light
darkman set dark
```

### Secrets and YubiKeys

The configurations only work with their secrets: the login password, pam-u2f
registrations, and the backup, Syncthing, media service and DNS credentials
are [agenix](https://github.com/ryantm/agenix) files in `secrets/`, decrypted
at boot with each host's SSH key. Editing them needs one of the two YubiKeys
(PIV identity and touch); an offline paper key is the recovery recipient. SSH,
commit signing and sudo on cinderace also use the YubiKeys.

Edit or create a secret from the development shell:

```sh
nix develop ~/nix
cd ~/nix/secrets
agenix -e <name>.age -i ~/.config/age/yubikeys.txt
```

After changing recipients in `secrets/secrets.nix`, rekey every secret:

```sh
agenix -r -i ~/.config/age/yubikeys.txt
```

## Inspiration and resources

Configurations:

- [NotAShelf/nyx](https://github.com/NotAShelf/nyx)

Structure:

- [mightyiam/dendritic](https://github.com/mightyiam/dendritic)
- [flake-parts](https://flake.parts)
- [vic/import-tree](https://github.com/vic/import-tree)

Tools:

- [Lix](https://lix.systems)
- [home-manager](https://github.com/nix-community/home-manager)
- [nix-darwin](https://github.com/nix-darwin/nix-darwin)
- [nh](https://github.com/nix-community/nh)
- [disko](https://github.com/nix-community/disko)
- [lanzaboote](https://github.com/nix-community/lanzaboote)
- [agenix](https://github.com/ryantm/agenix)
- [age-plugin-yubikey](https://github.com/str4d/age-plugin-yubikey)
- [Stylix](https://github.com/nix-community/stylix)
- [nvf](https://github.com/notashelf/nvf)
- [Monobiome](https://github.com/endofunctorio/monobiome)
