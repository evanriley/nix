# Installing NixOS on cinderace

This replaces Arch on the system SSD with NixOS built from this flake. It keeps
the **LUKS container** (its passphrase, recovery key and both FIDO2 YubiKey
enrollments) and the **Secure Boot keys enrolled in firmware**. Everything
inside the container is wiped: every btrfs subvolume, the ESP, and all Arch
history. `/mnt/Media` and `/mnt/Games` are not touched.

Home is not carried over wholesale. A trimmed, encrypted copy goes to
`/mnt/Media` for staging; after install you restore the things listed in
Phase 9 and delete the rest once you are sure nothing is missing.

## How to read this guide

- Work through the phases in order. Every phase starts with **Where** (which
  machine/shell) and ends with a **Checkpoint**. Do not continue past a
  checkpoint that fails.
- Command blocks are **bash**. On Arch your interactive shell is fish, so run
  `bash` first and stay in it for the whole phase: variables set early in a
  phase are used later in the same phase.
- `<angle brackets>` are values you type in. Everything else is literal.
- Lines starting with `#` inside blocks are comments; don't type them.

## Identifiers

These were read from the running Arch system on 2026-09-24. Stable by-uuid /
by-partuuid paths are used everywhere, because `nvme0/1/2` numbering can change
between boots.

| What | Stable path | Notes |
| --- | --- | --- |
| System SSD | Samsung 9100 PRO, 1.8T | Currently `nvme1n1` |
| ESP | `/dev/disk/by-partuuid/15eb8d56-918f-4388-8647-0c4a9a3ad9db` | Partition kept, filesystem recreated with label `BOOT` |
| LUKS partition | `/dev/disk/by-partuuid/a657bd8b-27fe-4dc7-8d93-520caa984b3c` | **Kept**. Mapped as `cryptroot` |
| btrfs (inside LUKS) | `/dev/mapper/cryptroot` | Recreated with label `cinderace` |
| Media drive | `/dev/disk/by-uuid/79cdba09-88c5-4f14-901b-11731d773abe` | ext4, kept, holds staging |
| Games drive | `/dev/disk/by-uuid/eaf05b17-caee-4b76-8754-9ffe20d4e0fb` | ext4, kept, has `SteamLibrary` |

The layout is declared in `modules/hosts/cinderace/disko.nix`. The btrfs
subvolumes (all `compress=zstd:3,noatime`):

| Subvolume | Mount | Why |
| --- | --- | --- |
| `@` | `/` | System state. NixOS generations are the rollback mechanism |
| `@home` | `/home` | Snapper-managed |
| `@nix` | `/nix` | Store; excluded from snapshots |
| `@log` | `/var/log` | Logs survive root changes |
| `@snapshots` | `/home/.snapshots` | Snapper snapshots of `@home` |

The ESP (2 GB) mounts at `/boot`. lanzaboote writes signed UKIs there.

---

## Phase 1 — The configuration is ready

**Where:** Arch, `~/nix`.

This guide assumes the flake already builds cinderace. Before touching
anything below, all of these must be true:

```bash
cd ~/nix
nix flake check
nix build .#nixosConfigurations.cinderace.config.system.build.toplevel
nix run .#nixosConfigurations.cinderace.config.system.build.vm   # boots, you can log in
nix develop -c sh -c 'command -v agenix age age-plugin-yubikey mkpasswd'
```

The devShell provides `agenix`, `age`, `age-plugin-yubikey` and `mkpasswd`. If
it doesn't exist yet, use this instead wherever the guide says `nix develop`:
`nix shell nixpkgs#age nixpkgs#age-plugin-yubikey nixpkgs#mkpasswd github:ryantm/agenix`.

**Checkpoint:** the build succeeds and the VM reaches GDM and logs in.

---

## Phase 2 — Save everything that isn't in a backup yet

**Where:** Arch, bash.

### 2.1 Push or park git work

Two repos in `~/Developer` had unpushed state on 2026-09-24:
`learn-clojure` (ahead 1) and `marlin` (no upstream). Check them all:

```bash
for d in ~/Developer/*/ ~/nix; do
  printf '%s: ' "$d"; git -C "$d" status -sb | head -1
done
```

Push anything ahead, or accept that it'll only exist in the home archive.

### 2.2 Run a final Borg backup

```bash
borgmatic create --verbosity 1 --stats
borgmatic repo-list --last 3
```

**Checkpoint:** the newest archive is `home-cinderance-<today>`. It keeps that
old-hostname prefix forever; the new system writes `home-cinderace-*` and only
prunes its own archives.

### 2.3 Prove the LUKS unlock methods before you depend on them

```bash
LUKS=/dev/disk/by-partuuid/a657bd8b-27fe-4dc7-8d93-520caa984b3c
sudo systemd-cryptenroll "$LUKS"
```

**Checkpoint:** the list shows `password` (or `recovery`) slots and two `fido2`
slots. Test each typed secret:

```bash
# Type the normal passphrase:
sudo cryptsetup open --test-passphrase "$LUKS" && echo PASSPHRASE-OK
# Type the recovery key (if you have one enrolled):
sudo cryptsetup open --test-passphrase "$LUKS" && echo RECOVERY-OK
```

**Checkpoint:** both print `...-OK`. **Stop here if either fails.** The
installer unlocks the disk with the passphrase, not the YubiKey.

About the YubiKeys: FIDO2 LUKS enrollments are non-resident. The credential
lives in the LUKS header, not on the key, so there is nothing to clean off the
keys, and they keep working because the header is kept.

### 2.4 Record Secure Boot state

```bash
sudo sbctl status
sudo sbctl list-files
sudo ls -la /var/lib/sbctl/keys
```

**Checkpoint:** `Secure Boot: ✓ Enabled`, `Setup Mode: ✓ Disabled`, and a
`keys/` directory containing `PK`, `KEK` and `db`. These same keys will sign
NixOS's boot files, so nothing is re-enrolled in firmware.

---

## Phase 3 — YubiKey PIV identities and the paper key

**Where:** Arch, bash, inside `nix develop ~/nix`.

agenix secrets are encrypted to four recipients:

- **cinderace's host SSH key.** The machine decrypts secrets with this at boot.
  No touch is needed.
- **Primary YubiKey (PIV).** Used when you edit or rekey secrets.
- **Backup YubiKey (PIV).**
- **Paper key.** An offline age key, for when both YubiKeys are unavailable.

PIV is a separate applet from FIDO2. Setting it up does not affect SSH, sudo,
lock screen or LUKS. Its PIN is also separate from your FIDO2 PIN.

### 3.1 Generate an identity on each key

Insert **only the primary** (serial 20477902):

```bash
nix develop ~/nix
ykman list --serials            # expect: 20477902
age-plugin-yubikey --generate --serial 20477902 --slot 1 \
  --name cinderace-primary --pin-policy once --touch-policy cached
```

The PIV PIN is still the factory default, so it asks you to set a new PIN. It
sets the PUK to the same value and replaces the management key with a random
one stored under the PIN. Record the PIV PIN in Bitwarden as
"YubiKey 20477902 PIV PIN".

Swap to **only the backup** (serial 20477782) and repeat:

```bash
ykman list --serials            # expect: 20477782
age-plugin-yubikey --generate --serial 20477782 --slot 1 \
  --name cinderace-backup --pin-policy once --touch-policy cached
```

`cached` touch means a rekey of many files asks for one touch, not one per file.

### 3.2 Save identity stubs and collect recipients

The stubs aren't secret. They tell `age` which YubiKey slot to ask:

```bash
mkdir -p ~/.config/age
: > ~/.config/age/yubikeys.txt
for s in 20477902 20477782; do
  echo "Insert $s, then press Enter"; read -r
  age-plugin-yubikey --identity --serial "$s" --slot 1 >> ~/.config/age/yubikeys.txt
done
grep -o 'age1yubikey1[0-9a-z]*' ~/.config/age/yubikeys.txt
```

**Checkpoint:** two different `age1yubikey1…` recipients print.

### 3.3 Paper key

```bash
age-keygen -o ~/paper-age.key
cat ~/paper-age.key
```

Write the `AGE-SECRET-KEY-1…` line on paper, or print it, and store it with
your LUKS recovery key. Note the `# public key: age1…` line, then:

```bash
shred -u ~/paper-age.key
```

---

## Phase 4 — Host key and secrets

**Where:** Arch, bash, inside `nix develop ~/nix`.

### 4.1 Staging directories

```bash
STAGE=/mnt/Media/nixos-migration
sudo install -d -o evan -g evan -m 700 "$STAGE"
sudo install -d -m 700 /root/migration-system/etc/ssh /root/migration-system/var/lib
```

### 4.2 Generate cinderace's host key now

Secrets are encrypted to this key before NixOS is installed:

```bash
sudo ssh-keygen -t ed25519 -N '' -C root@cinderace \
  -f /root/migration-system/etc/ssh/ssh_host_ed25519_key
sudo cat /root/migration-system/etc/ssh/ssh_host_ed25519_key.pub
```

### 4.3 Fill in the recipients

Edit `~/nix/secrets/secrets.nix`. Replace the placeholders with the two
`age1yubikey1…` recipients, the paper `age1…` public key and the
`hosts.cinderace` `ssh-ed25519 …` line. Only public keys go in this file.
Secrets bound to one machine live in `secrets/<hostname>/`; the user
password and the ListenBrainz token are shared by all hosts.

### 4.4 Encrypt each secret

Secrets are created from files, so nothing passes through your shell history.
`EDITOR="cp -- <file>"` makes `agenix -e` copy that file in as the cleartext.
The repository holds unencrypted placeholders so the configuration builds
before this phase; remove them first. Do this from `~/nix/secrets`:

```bash
cd ~/nix/secrets
rm -f -- *.age cinderace/*.age
enc() { EDITOR="cp -- $2" agenix -e "$1"; }
```

| Secret file | Source | How |
| --- | --- | --- |
| `evan-password.age` | Your login password as a yescrypt hash | See below |
| `cinderace/u2f-mappings.age` | `/etc/security/yubikey-u2f` (pam-u2f registrations) | `sudo cat /etc/security/yubikey-u2f > /tmp/u2f; enc cinderace/u2f-mappings.age /tmp/u2f; shred -u /tmp/u2f` |
| `cinderace/borg-passphrase.age` | `~/.local/share/borgmatic-secrets/repository-passphrase` | `enc cinderace/borg-passphrase.age <that path>` |
| `cinderace/borg-ssh-key.age` | `~/.local/share/borgmatic-secrets/id_ed25519-borgbase` | `enc cinderace/borg-ssh-key.age <that path>` |
| `cinderace/syncthing-cert.age` | `~/.local/state/syncthing/cert.pem` | `enc …` (keeps the device ID) |
| `cinderace/syncthing-key.age` | `~/.local/state/syncthing/key.pem` | `enc …` |
| `listenbrainz-token.age` | `~/.config/listenbrainz-mpd/token` | `enc …` |
| `cinderace/lidarr.env.age` | `ApiKey` from `~/.local/share/media-stack/lidarr/config.xml` | See below |
| `cinderace/slskd.env.age` | Credentials in `~/.local/share/media-stack/slskd/slskd.yml` | See below |
| `cinderace/soularr-config.age` | `~/.local/share/media-stack/soularr/config.ini`, edited | See below |

**Password hash.** Use the **same password as now** so the restored GNOME
keyring still unlocks at login:

```bash
umask 077; mkpasswd -m yescrypt > /tmp/pw.hash   # prompts, no echo
enc evan-password.age /tmp/pw.hash; shred -u /tmp/pw.hash
```

**Lidarr, slskd and Soularr.** Write each env file with an editor, not `echo`,
so values stay out of history. Use `/tmp/x.env` with `umask 077`, `enc` it,
then `shred -u` it.

- `lidarr.env`: one line, `LIDARR__AUTH__APIKEY=<ApiKey from config.xml>`.
  This keeps Soularr's and the recommendations script's API key valid.
- `slskd.env`: `SLSKD_SLSK_USERNAME=`, `SLSKD_SLSK_PASSWORD=` (the `soulseek:`
  block), `SLSKD_USERNAME=`, `SLSKD_PASSWORD=` (the `web: authentication:`
  block) and `SLSKD_API_KEY=` if your yml defines an API key for Soularr.
- `soularr-config`: copy `config.ini` to `/tmp` and change the two host URLs.
  Soularr still runs in a container, now on the host network, so there are no
  `lidarr`/`slskd` container hostnames:
  - `[Lidarr] host_url = http://127.0.0.1:8686`
  - `[Slskd] host_url = http://127.0.0.1:5030`

  Leave the other settings alone. `[Slskd] download_dir = /downloads` is the
  container's mount of `/mnt/Media/Downloads/slskd/complete`.

`/data` stays valid on NixOS because the config bind-mounts `/mnt/Media` at
`/data`. Every path stored in Lidarr's database (`/data/Music`,
`/data/Downloads/slskd/...`) keeps working, so no remapping is needed.

### 4.5 Verify, commit

```bash
cd ~/nix/secrets
for f in *.age cinderace/*.age; do
  agenix -d "$f" -i ~/.config/age/yubikeys.txt >/dev/null \
    && echo "ok $f" || echo "FAIL $f"
done
cd ~/nix
nix build .#nixosConfigurations.cinderace.config.system.build.toplevel
git add -A && git commit -m "Add cinderace secrets and recipients"
```

**Checkpoint:** every file prints `ok` after a touch, and the build still
succeeds. Committing is required: flakes only include tracked files, so
`nixos-install` does not see uncommitted `.age` files.

---

## Phase 5 — Stage what the installer needs

**Where:** Arch, bash. Choose a **staging passphrase** now; the installer asks
for it. It only protects these temporary archives.

### 5.1 System archive: host key, Secure Boot keys, device state

Tailscale keeps its node identity, and Bluetooth keeps its pairings (same
adapter, same MAC):

```bash
STAGE=/mnt/Media/nixos-migration
sudo cp -a /var/lib/sbctl /var/lib/tailscale /var/lib/bluetooth /root/migration-system/var/lib/
sudo tar -C /root/migration-system -cpf - . | zstd -T0 | age -p -o "$STAGE/system.tar.zst.age"
```

### 5.2 LUKS header backup

This lets you recover if the header is ever damaged:

```bash
sudo cryptsetup luksHeaderBackup /dev/disk/by-partuuid/a657bd8b-27fe-4dc7-8d93-520caa984b3c \
  --header-backup-file /root/luks-header.img
sudo cat /root/luks-header.img | age -p -o "$STAGE/luks-header.img.age"
sudo shred -u /root/luks-header.img
```

Keep `luks-header.img.age` permanently, e.g. copy it next to the paper key. A
header backup is only as sensitive as the weakest key in it.

### 5.3 Home archive

These are excluded because they're re-downloadable or regenerate: caches,
Unsloth (20 GB), WoW game data (137 GB), Steam game files, Podman image storage
and Lidarr cover art (8.5 GB). The archive is roughly 10–15 GB.

Stop the media containers first so Lidarr's database is copied consistently.
They can stay stopped until the wipe.

```bash
systemctl --user stop soularr slskd lidarr
tar -C /home \
  --exclude='evan/.cache' \
  --exclude='evan/.unsloth' \
  --exclude='evan/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/Data' \
  --exclude='evan/.local/share/containers' \
  --exclude='evan/.local/share/Steam/steamapps/common' \
  --exclude='evan/.local/share/Steam/steamapps/shadercache' \
  --exclude='evan/.local/share/media-stack/lidarr/MediaCover' \
  --exclude='evan/.var/app/*/cache' \
  -cpf - evan | zstd -T0 | age -p -o "$STAGE/home.tar.zst.age"
```

### 5.4 Repository copy

This needs no auth on the installer:

```bash
git clone --no-local ~/nix "$STAGE/nix"
```

### 5.5 Verify the staging

```bash
ls -lh "$STAGE"
age -d "$STAGE/system.tar.zst.age" | zstd -d | tar -tvf - | head
age -d "$STAGE/home.tar.zst.age"   | zstd -d | tar -tf - | grep -c .
git -C "$STAGE/nix" log --oneline -1
sudo rm -rf /root/migration-system
```

**Checkpoint:** the system archive lists `./etc/ssh/ssh_host_ed25519_key` and
`./var/lib/sbctl/keys/...`. The home archive lists a large count without
errors. The clone's last commit is your secrets commit.

### 5.6 Installer USB

Download and verify the ISO:

```bash
cd ~/Downloads
curl -LO https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-x86_64-linux.iso
curl -LO https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-x86_64-linux.iso.sha256
echo "expected: $(cut -d' ' -f1 latest-nixos-minimal-x86_64-linux.iso.sha256)"
echo "actual:   $(sha256sum latest-nixos-minimal-x86_64-linux.iso | cut -d' ' -f1)"
```

**Checkpoint:** the two hashes are identical.

Insert the USB stick and find it. It's the only `usb-` entry in:

```bash
ls -l /dev/disk/by-id/ | grep usb-
```

Write the ISO. This is destructive to the USB only:

```bash
USB=/dev/disk/by-id/<usb-…-0:0 entry, whole disk, no -partN>
sudo dd if=latest-nixos-minimal-x86_64-linux.iso of="$USB" bs=4M status=progress oflag=sync
```

---

## Phase 6 — Firmware: let the installer boot

**Where:** Arch → firmware.

The NixOS ISO isn't signed by your keys, so Secure Boot must be off for the
install. **Turn it off, do not clear keys.**

```bash
systemctl reboot --firmware-setup
```

In the ASRock UEFI (Security → Secure Boot):

- Set **Secure Boot** to **Disabled**.
- **Do not** choose "Reset to Setup Mode", "Clear Secure Boot Keys", "Restore
  Factory Keys" or "Delete all keys". Your PK/KEK/db must stay enrolled.

Save, and boot the USB from the boot override menu. Pick the **UEFI** entry for
the stick.

---

## Phase 7 — Install

**Where:** NixOS installer console. Become root and use bash:

```bash
sudo -i
```

### 7.1 Network, staging and repository

Ethernet (RTL8126) should come up by itself:

```bash
ping -c 3 cache.nixos.org

LUKS=/dev/disk/by-partuuid/a657bd8b-27fe-4dc7-8d93-520caa984b3c
ESP=/dev/disk/by-partuuid/15eb8d56-918f-4388-8647-0c4a9a3ad9db
MEDIA=/dev/disk/by-uuid/79cdba09-88c5-4f14-901b-11731d773abe
STAGE=/media-staging/nixos-migration
lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL "$(readlink -f "$LUKS")" "$(readlink -f "$ESP")" "$(readlink -f "$MEDIA")"
```

**Checkpoint:** you should see:

- `LUKS` is a `crypto_LUKS` partition, about 1.8T.
- `ESP` is a `vfat` partition labelled `ARCH_EFI`, about 2G, on the **same**
  disk as LUKS.
- `MEDIA` is `ext4` labelled `Media`, about 3.6T.

If anything differs, stop.

Mount the staging drive read-only and copy the repository. The install runs
from a root-owned copy, which avoids git ownership errors:

```bash
mkdir -p /media-staging && mount -o ro "$MEDIA" /media-staging
cp -r "$STAGE/nix" /root/nix
git -C /root/nix log --oneline -1
```

### 7.2 Unlock with the passphrase

```bash
cryptsetup open "$LUKS" cryptroot
ls /dev/mapper/cryptroot
```

### 7.3 Wipe inside the container, then format and mount with disko

**This is the point of no return for Arch and the old home.**

`wipefs` clears the old btrfs and the old ESP filesystem. disko then creates
everything declared in `modules/hosts/cinderace/disko.nix` that is missing.
It adopts the existing partitions and the open LUKS container without
recreating them: no `luksFormat`, and the partition table keeps its layout and
GUIDs. `checks.x86_64-linux.cinderace-disko-adopt` tests this sequence
against a copy of this disk layout.

```bash
wipefs -a /dev/mapper/cryptroot
wipefs -a "$ESP"
nix --extra-experimental-features 'nix-command flakes' \
  run /root/nix#disko -- --mode format,mount --flake /root/nix#cinderace
findmnt -R /mnt
```

disko prints two `Error encountered; not saving changes.` lines from `sgdisk`.
That is its attempt to create the two partitions failing because they
exist. It then only sets their names and types.

**Checkpoint:** `findmnt` shows `/mnt`, `/mnt/home`, `/mnt/home/.snapshots`,
`/mnt/nix` and `/mnt/var/log` on `cryptroot`, and `/mnt/boot` as vfat.

### 7.4 Restore the host key, Secure Boot keys and device state

```bash
nix-shell -p age zstd --run \
  "age -d $STAGE/system.tar.zst.age | zstd -d | tar -xpf - --numeric-owner -C /mnt"
ls -l /mnt/etc/ssh/ssh_host_ed25519_key /mnt/var/lib/sbctl/keys
```

**Checkpoint:** the host key is `-rw------- root`, and `keys/` has `PK KEK db`.

### 7.5 Install

Evan's working copy goes in their home:

```bash
install -d -o 1000 -g 1000 -m 700 /mnt/home/evan
cp -a "$STAGE/nix" /mnt/home/evan/nix
chown -R 1000:1000 /mnt/home/evan/nix

nixos-install --root /mnt --flake /root/nix#cinderace --no-root-passwd \
  --option experimental-features 'nix-command flakes'
```

This downloads and builds the whole system. The final step installs the
bootloader. lanzaboote signs everything with the restored keys.

**If the bootloader step fails:** see Troubleshooting → "lanzaboote fails
during install".

### 7.6 Verify before rebooting

```bash
nixos-enter --root /mnt -c 'sbctl verify'
ls /mnt/boot/EFI/Linux /mnt/boot/EFI/systemd
efibootmgr -v
```

**Checkpoint:** `sbctl verify` shows ✓ signed for `systemd-bootx64.efi`,
`BOOTX64.EFI` and the `nixos-generation-*.efi` UKIs. `efibootmgr` has a
"Linux Boot Manager" entry pointing to `\EFI\systemd\systemd-bootx64.efi`.

Remove stale Arch entries, if any are shown (e.g. a direct-UKI entry):

```bash
efibootmgr -b <XXXX> -B
```

### 7.7 Stage the home archive inside the new home

The next step is on the installed system, but the archive is decrypted now
because the Media drive is already mounted:

```bash
install -d -o 1000 -g 1000 -m 700 /mnt/home/evan/.arch-home
nix-shell -p age zstd --run \
  "age -d $STAGE/home.tar.zst.age | zstd -d | tar -xpf - --numeric-owner -C /mnt/home/evan/.arch-home"
ls /mnt/home/evan/.arch-home/evan
```

### 7.8 Unmount and reboot

```bash
umount /media-staging
umount -R /mnt
cryptsetup close cryptroot
reboot
```

Remove the USB while the firmware logo shows.

---

## Phase 8 — First boot

**Where:** cinderace, NixOS. Secure Boot is still off.

- [ ] Plymouth asks to unlock and touching a YubiKey works. If it only asks
      for a passphrase, see Troubleshooting.
- [ ] GDM appears. Log in as evan with your password, and niri starts.
- [ ] `sudo true` works with touch only.

Now re-enable Secure Boot:

```bash
systemctl reboot --firmware-setup
```

Set Secure Boot → **Enabled**, then save. Once back in NixOS:

```bash
bootctl status | grep -i 'secure boot'   # "enabled (user)"
sudo sbctl status                        # Secure Boot ✓ Enabled
```

Then verify the rest:

- [ ] `sudo ls /run/agenix` lists every secret.
- [ ] Locking and unlocking with touch works (Mod+Alt+L). Password-only
      unlock works with the keys removed.
- [ ] Both display modes: `display-mode` switching 6K/165 ↔ 3K/330.
- [ ] Audio, Bluetooth, portals (screen share, file picker).
- [ ] `systemctl --user --failed` lists nothing. `systemctl --user status waybar
      swaync darkman display-mode swayidle` are active.
- [ ] `systemctl status lidarr slskd podman-soularr syncthing` are active.

---

## Phase 9 — Restore selected data

**Where:** cinderace, bash as evan.

`A` is the unpacked Arch home. `--ignore-existing` never overwrites a file
home-manager already placed:

```bash
A=~/.arch-home/evan
r() { rsync -a --ignore-existing "$A/$1" "$(dirname ~/"$1")/"; }

r .ssh                        # FIDO2 SSH handles, known_hosts, software keys
r sync                        # Syncthing folder (avoids a full resync)
r Developer
r Pictures
r Downloads
r .local/share/keyrings       # GNOME keyring; same password → unlocks at login
r .local/share/fish/fish_history
r .config/mozilla             # Firefox profile
r .config/BraveSoftware
r .local/share/qutebrowser
r .local/state/yubikey-setup  # historical setup/test records
r .local/bin/scapectl         # prebuilt binaries not packaged in nixpkgs
r .local/bin/manta
chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_*
```

Then check:

```bash
ssh -T git@github.com                       # touch → "Hi evanriley!"
T=$(mktemp -d) && git -C "$T" init -q && \
  git -C "$T" commit -q --allow-empty -m "signing test" && \
  git -C "$T" log --show-signature -1; rm -rf "$T"   # touch → "Good "git" signature"
```

**Media services.** Move Lidarr's database into the service's directory. slskd
and Soularr state and the recommendations cache are small and optional:

```bash
sudo systemctl stop lidarr
sudo rsync -a --exclude logs --exclude 'logs.db*' \
  "$A/.local/share/media-stack/lidarr/" /var/lib/lidarr/
sudo chown -R lidarr:media /var/lib/lidarr
sudo systemctl start lidarr

sudo systemctl stop slskd
sudo rsync -a "$A/.local/share/media-stack/slskd/data/" /var/lib/slskd/data/
sudo chown -R slskd:media /var/lib/slskd
sudo systemctl start slskd

sudo rsync -a "$A/.local/share/media-stack/soularr/failed_imports.json" /var/lib/soularr/
sudo systemctl restart podman-soularr

# The service uses DynamicUser; systemd fixes ownership on its next start.
sudo install -d /var/lib/private/listenbrainz-recommendations
sudo cp "$A/.local/state/arch-switch/listenbrainz-release-groups.json" \
  /var/lib/private/listenbrainz-recommendations/
```

Library permissions: the services now run as their own users in the `media`
group, not as evan. Give the group write access once:

```bash
sudo chgrp -R media /mnt/Media/Music /mnt/Media/Downloads
sudo chmod -R g+rwX /mnt/Media/Music /mnt/Media/Downloads
sudo find /mnt/Media/Music /mnt/Media/Downloads -type d -exec chmod g+s {} +
```

Open Lidarr at `http://127.0.0.1:8686`. **Checkpoint:** artists are present,
the root folder `/data/Music` is healthy, and slskd shows as a connected
download client.

**Games.**

- Steam: add `/mnt/Games/SteamLibrary` under Settings → Storage.
- WoW: reinstall through Faugus/Battle.net, then copy
  `…/World of Warcraft/_retail_/WTF` back from `$A/Faugus/…` before launching.

**Backups.**

```bash
sudo systemctl start borgmatic.service
journalctl -u borgmatic -n 30
```

The first run rebuilds Borg's local cache under `/root/.cache/borg`, so it
takes longer than later runs.

**Checkpoint:** a `home-cinderace-*` archive exists and the old
`home-cinderance-*` archives are untouched.

---

## Phase 10 — Cleanup (after ~30 days)

Once you haven't reached for `~/.arch-home` in a month:

```bash
rm -rf ~/.arch-home
sudo rm -rf /mnt/Media/nixos-migration   # keep a copy of luks-header.img.age elsewhere first
```

After that, also:

- Retire `~/sync/dotfiles` and `~/sync/arch-switch`: remove the folders from
  Syncthing, and archive the GitHub `dotfiles` repo.
- Old `home-cinderance-*` Borg archives expire only if you prune them manually.

---

## Troubleshooting

**Only a passphrase prompt, no FIDO2 prompt.** Type the passphrase to boot.
Then check the config sets `boot.initrd.systemd.enable = true` and
`crypttabExtraOpts = [ "fido2-device=auto" ]` for `cryptroot`, and run
`sudo systemd-cryptenroll /dev/disk/by-partuuid/a657bd8b-27fe-4dc7-8d93-520caa984b3c`.
It should still list both fido2 slots. Rebuild and reboot.

**lanzaboote fails during install.** In `/root/nix`, make the host use
plain systemd-boot for the first install: drop the secure-boot feature from
the host's imports and commit. Re-run `nixos-install`, boot with Secure Boot
off, restore the import, `sudo nixos-rebuild switch`, check `sbctl verify`,
then enable Secure Boot in firmware.

**Secure Boot violation after enabling it.** Disable it in firmware, boot, and
run `sudo sbctl verify`. Unsigned files mean `pkiBundle` isn't
`/var/lib/sbctl` or the keys weren't restored. `sudo sbctl status` showing
"Setup Mode" means the firmware keys were cleared: re-enroll with
`sudo sbctl enroll-keys --microsoft` in setup mode.

**Can't log in (password rejected).** The password secret didn't decrypt.
`users.mutableUsers = false`, so `passwd` changes do not survive activation.
Boot the USB and run 7.1 and 7.2, then mount with
`nix run /root/nix#disko -- --mode mount --flake /root/nix#cinderace`. In
`/root/nix/modules/system/users.nix`, temporarily replace `hashedPasswordFile`
with `hashedPassword = "<output of mkpasswd -m yescrypt>";`, commit, and
re-run the `nixos-install` command from 7.5. After booting, compare
`/etc/ssh/ssh_host_ed25519_key.pub` with the `cinderace` recipient in
`secrets/secrets.nix`, fix and rekey, then revert the change.

**Want to fall back.** There's no Arch left to boot. The recovery path is the
USB → `nixos-enter` for fixes. Borg (`home-cinderance-*`) and
`/mnt/Media/nixos-migration` hold your data, and
`/var/lib/system-recovery/system-config.tar` inside the last Arch Borg archive
has the old `/etc`.
