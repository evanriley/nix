# nix

NixOS and nix-darwin configurations for my machines. They depend on private
inputs and secrets, so they won't build as-is elsewhere.

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
`berkeley-mono`, `manta`, `helix`, `kak-*`, `friendly-snippets`, `monobiome`
and `lanzaboote` are updated by hand.

After a bad update, restore the previous lock and switch again:

```sh
git -C ~/nix checkout HEAD~1 -- flake.lock
```

`nh home switch` needs GitHub SSH access to fetch the private
`evanriley/berkeley-mono` and `evanriley/manta` inputs.

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

1. Add it to `secrets/secrets.nix`: `hostSecrets "<host>" [ "<name>.age" ]` for one
   host, or `shared [ "<host>" … ] "<name>.age"` for several.
2. Create it with the edit command above.
3. Declare it: `age.secrets.<name>.file = inputs.self + "/secrets/<path>.age";`
4. `git add` the `.age` file and switch.

After changing recipients in `secrets/secrets.nix`, rekey:

```sh
cd ~/nix/secrets
nix develop ~/nix -c agenix -r -i ~/.config/age/yubikeys.txt
```

### Shell history

[Atuin](https://atuin.sh) syncs shell history between hosts, encrypted with
`secrets/atuin-key.age`, which every host in `hosts` in `secrets/secrets.nix`
decrypts. Log in once per host:

```sh
atuin login -u <username>
```

## Adding a host

Profiles in `modules/profiles/`:

| Module | Contents |
| --- | --- |
| `nixos.base`, `darwin.base` | Nix, agenix, user, locale, networking, fish |
| `nixos.workstation` | `base` plus boot, zram, NextDNS, YubiKey, GDM, niri, umbriel, Plymouth, audio, Bluetooth, fonts |
| `homeManager.cli` | Home basics, dotfiles, shell, Atuin, git, jj, Kakoune, Neovim, theme, agent config |
| `homeManager.workstation` | `cli` plus browsers, Discord, mpv, Bitwarden, YubiKey tools |
| `homeManager.desktop` | `workstation` plus the Linux session, niri, umbriel and desktop apps |

1. Create `modules/hosts/<host>/configuration.nix` with
   `flake.nixosConfigurations.<host>` (or `darwinConfigurations`) and a
   `flake.modules.nixos.<host>` module that imports `base` or `workstation`
   and the features it needs, and sets `networking.hostName` and
   `system.stateVersion`. A `flake.modules.homeManager.<host>` module that
   imports `cli`, `workstation` or `desktop` and sets `home.stateVersion` adds
   `homeConfigurations."evan@<host>"`.
2. Add the host's `/etc/ssh/ssh_host_ed25519_key.pub` to `hosts` in
   `secrets/secrets.nix`, which makes it a recipient of `atuin-key.age`. On
   NixOS, add it to `evan-password.age`. Add it to any other shared secret it
   uses, then rekey.
3. For `backup`: create a BorgBase repository, add its ID to `repos` in
   `modules/services/backup.nix`, and create `<host>/borg-passphrase.age` and
   `<host>/borg-ssh-key.age`. Modules add their own state to
   `services.borgmatic.configurations.home`.
4. For `syncthing`: add the device ID to `devices` in
   `modules/services/syncthing.nix`. On NixOS, also create
   `<host>/syncthing-cert.age` and `<host>/syncthing-key.age`.

5. Add the host to the machine list in `home/config/ai/AGENTS.md` and
   `home/config/ai/skills/nix-environment/SKILL.md`.

CI evaluates every host in `nixosConfigurations` and `darwinConfigurations`.

## First-time setup

### ninetales

1. Install [Lix](https://lix.systems/install/) and [Homebrew](https://brew.sh).
2. Clone with Nix's OpenSSH (Apple's lacks FIDO2 for the YubiKey):

   ```sh
   nix shell nixpkgs#openssh -c git clone git@github.com:evanriley/nix.git ~/nix
   ```

3. Apply the system, then home:

   ```sh
   sudo nix run --inputs-from ~/nix nix-darwin -- switch --flake ~/nix#ninetales
   nix run --inputs-from ~/nix home-manager -- switch --flake ~/nix#evan@ninetales
   ```

Then, by hand:

- Grant Accessibility to OmniWM, skhd and qutebrowser, and Input Monitoring to
  OmniWM.
- Tailscale app: allow its VPN configuration, log in, and turn off Use
  Tailscale DNS (NextDNS resolves, forwarding `ts.net` to MagicDNS).
- In Firefox, `about:profiles` → Create a New Profile → Choose Folder
  `~/Library/Application Support/org.nixos.firefox/Profiles/default` → Set as
  default profile.
- System Settings → Spotlight: exclude `~/nix`.
- If a Dock icon shows `?`, run `killall Dock`.
- Log in to Atuin (see [Shell history](#shell-history)).

### cinderace

1. Boot the NixOS installer, clone to `~/nix`, and partition and mount the
   disks with disko.
2. Restore the host SSH key and the Secure Boot keys from Borg into `/mnt`
   (see [Restoring from Borg](#restoring-from-borg)). The agenix secrets,
   including the login password, only decrypt with that host key.

   ```sh
   cd /mnt
   sudo -E nix shell nixpkgs#borgbackup -c borg extract ::<archive> etc/ssh/ssh_host_ed25519_key etc/ssh/ssh_host_ed25519_key.pub var/lib/sbctl
   ```

3. `nixos-install --flake ~/nix#cinderace`
4. After the first login, log in to Atuin (see
   [Shell history](#shell-history)).

## Restoring from Borg

Both hosts back up daily to BorgBase; `repos` in `modules/services/backup.nix`
maps each host to its repository.

```sh
sudo borgmatic repo-list --last 5
sudo borgmatic extract --archive latest --path <home>/<path> --destination /tmp/restore
```

`<home>` is `home/evan` on cinderace and `Users/evan` on ninetales.

On a new machine, borgmatic has no credentials yet. The passphrase and the key
export (`borg-key-<host>`) are in Bitwarden; the SSH key decrypts with a
YubiKey:

```sh
cd ~/nix/secrets
nix develop ~/nix -c agenix -d <host>/borg-ssh-key.age -i ~/.config/age/yubikeys.txt > /tmp/borg-ssh-key
chmod 600 /tmp/borg-ssh-key
export BORG_RSH="ssh -i /tmp/borg-ssh-key" BORG_REPO="ssh://<repo>@<repo>.repo.borgbase.com/./repo"
nix shell nixpkgs#borgbackup -c borg list
nix shell nixpkgs#borgbackup -c borg extract ::<archive> <path>
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
