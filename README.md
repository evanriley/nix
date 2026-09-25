# nix

| Host | Hardware | System | Status |
| --- | --- | --- | --- |
| `cinderace` | Desktop: Ryzen 7 9800X3D, Radeon RX 9070 XT | NixOS, x86_64-linux | Active |
| `ninetales` | MacBook Pro, M1 Pro | nix-darwin, aarch64-darwin | Active |

## Usage

```sh
git clone git@github.com:evanriley/nix.git ~/nix
```

| | cinderace | ninetales |
| --- | --- | --- |
| Apply system | `nh os switch` | `nh darwin switch` |
| Apply home | `nh home switch` | `nh home switch` |
| Build only | `nh os build`, `nh home build` | `nh darwin build`, `nh home build` |
| Roll back system | `nh os rollback` | `sudo darwin-rebuild --rollback` |
| Roll back home | `home-manager generations`, then `<path>/activate` | `home-manager generations`, then `<path>/activate` |

Update inputs with `nix flake update --flake ~/nix`. The `update-flake-lock`
workflow opens a pull request every Monday for the public, unpinned inputs;
`berkeley-mono`, `helix`, `kak-*`, `friendly-snippets`, `monobiome` and
`lanzaboote` are updated by hand.

After a bad update, restore the previous lock and switch again:

```sh
git -C ~/nix checkout HEAD~1 -- flake.lock
```

`nh home switch` needs GitHub SSH access to fetch the private
`evanriley/berkeley-mono` input.

### Secrets

Secrets are [agenix](https://github.com/ryantm/agenix) files in `secrets/`,
decrypted at boot with each host's SSH key. Editing needs a YubiKey; the paper
key is the recovery recipient.

Edit a secret:

```sh
cd ~/nix/secrets
nix develop ~/nix -c agenix -e <path>.age -i ~/.config/age/yubikeys.txt
```

Add a secret:

1. Add it to `secrets/secrets.nix` (`hostSecrets "<host>" [ … ]` or `shared [ … ]`).
2. Create it with the edit command above.
3. Declare it: `age.secrets.<name>.file = inputs.self + "/secrets/<path>.age";`
4. `git add` the `.age` file and switch.

After changing recipients in `secrets/secrets.nix`, rekey:

```sh
cd ~/nix/secrets
nix develop ~/nix -c agenix -r -i ~/.config/age/yubikeys.txt
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
