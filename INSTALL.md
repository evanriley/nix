# Installing NixOS on cinderace

This replaces Arch on the system SSD with NixOS built from this flake.

| Kept | Recreated | Untouched |
| --- | --- | --- |
| The LUKS container and its header: passphrase, recovery key, both FIDO2 YubiKey enrollments | Everything inside the LUKS container (all btrfs subvolumes, all Arch history) | `/mnt/Media` (3.6T ext4) |
| The GPT partition table and both partition GUIDs | The ESP filesystem (old UKIs and loader entries) | `/mnt/Games` (3.6T ext4) |
| Secure Boot keys enrolled in firmware (PK, KEK, db) | | BorgBase repository and its `home-cinderance-*` archives |

Home is not carried over wholesale. An encrypted, trimmed copy is staged on
`/mnt/Media`; selected parts are restored on first boot and the rest stays in
`~/.arch-home` until Phase 10.

## Contents

1. [Before starting](#before-starting)
2. [Phase 1: Verify the configuration](#phase-1-verify-the-configuration)
3. [Phase 2: Save state that is not backed up](#phase-2-save-state-that-is-not-backed-up)
4. [Phase 3: YubiKey PIV identities and the paper key](#phase-3-yubikey-piv-identities-and-the-paper-key)
5. [Phase 4: Host key and secrets](#phase-4-host-key-and-secrets)
6. [Phase 5: Stage what the installer needs](#phase-5-stage-what-the-installer-needs)
7. [Phase 6: Firmware](#phase-6-firmware)
8. [Phase 7: Install](#phase-7-install)
9. [Phase 8: First boot and user environment](#phase-8-first-boot-and-user-environment)
10. [Phase 9: Services, games and backups](#phase-9-services-games-and-backups)
11. [Phase 10: Cleanup](#phase-10-cleanup)
12. [Troubleshooting](#troubleshooting)

## Conventions

- Phases run in order. Each step names **where** it runs and ends with a
  **Checkpoint**. Do not continue past a checkpoint that fails.
- Command blocks are **bash**. On Arch the interactive shell is fish: run
  `bash` at the start of each phase and stay in it, because variables set in a
  step are used by later steps of the same phase. On the installed system the
  login shell is also fish; the same rule applies.
- `<angle brackets>` are values to substitute. Everything else is literal.
- `(touch)` in a comment means the command waits for a YubiKey touch; the key
  blinks while it waits.

## Before starting

Have these at hand:

| Item | Used in |
| --- | --- |
| Both YubiKeys (primary 20477902, backup 20477782) | Phases 3, 4, 8 |
| LUKS passphrase and LUKS recovery key | Phases 2, 7 |
| Login password (unchanged) | Phases 4, 8 |
| Bitwarden access on another device (phone) | Recording PINs and the staging passphrase |
| A USB stick of at least 2 GB that may be erased | Phase 5 |
| Paper and pen, or a printer | Phase 3 (paper key) |
| Wired Ethernet on the RTL8126 port | Phases 7, 8 |

Time: Phases 1–5 about 2 hours; Phases 6–8 about 1 hour plus download time;
Phase 9 about 30 minutes plus game downloads.

### Identifiers

Read from the running Arch system on 2026-09-24. Stable paths are used
everywhere because `nvme0/1/2` numbering can change between boots.

| What | Stable path | After install |
| --- | --- | --- |
| System SSD | `/dev/disk/by-id/nvme-Samsung_SSD_9100_PRO_2TB_S7YCNJ0Y201797K` | Same |
| ESP | `/dev/disk/by-partuuid/15eb8d56-918f-4388-8647-0c4a9a3ad9db` | vfat, label `BOOT`, mounted at `/boot` |
| LUKS partition | `/dev/disk/by-partuuid/a657bd8b-27fe-4dc7-8d93-520caa984b3c` | Unchanged, opened as `cryptroot` |
| btrfs | `/dev/mapper/cryptroot` | New filesystem, label `cinderace` |
| Media drive | `/dev/disk/by-uuid/79cdba09-88c5-4f14-901b-11731d773abe` | `/mnt/Media`, bind-mounted at `/data` |
| Games drive | `/dev/disk/by-uuid/eaf05b17-caee-4b76-8754-9ffe20d4e0fb` | `/mnt/Games` |

The disk layout is declared in `modules/hosts/cinderace/disko.nix`. btrfs
subvolumes, all mounted with `compress=zstd:3,noatime`:

| Subvolume | Mount | Purpose |
| --- | --- | --- |
| `@` | `/` | System; NixOS generations provide rollback |
| `@home` | `/home` | User data; Snapper timeline snapshots |
| `@snapshots` | `/home/.snapshots` | Snapper snapshots of `@home` |
| `@nix` | `/nix` | Nix store |
| `@log` | `/var/log` | Logs, mounted early in boot |

---

## Phase 1: Verify the configuration

**Where:** Arch, bash, in `~/nix`.

### 1.1 Repository state

```bash
cd ~/nix
git status -sb          # expect: ## main...origin/main, nothing else
git pull --ff-only
```

**Checkpoint:** no uncommitted changes and the branch matches `origin/main`.

### 1.2 Build and test

```bash
nix flake check                                                   # runs both VM tests
nix build .#nixosConfigurations.cinderace.config.system.build.toplevel
nix build '.#homeConfigurations."evan@cinderace".activationPackage'   # (touch) first time: fetches Berkeley Mono
nix develop -c sh -c 'command -v agenix age age-plugin-yubikey mkpasswd'
```

**Checkpoint:** every command succeeds; the last prints four paths.

### 1.3 Boot the VM

```bash
nix run .#nixosConfigurations.cinderace.config.system.build.vm
```

A QEMU window opens with software rendering, so it is slow.

**Checkpoint:** GDM appears; logging in as `evan` with password `vm` starts
niri. Lidarr, slskd and Syncthing fail in the VM because it has no host key to
decrypt secrets; everything else starts. Close the window to stop the VM, then
remove its disk image:

```bash
rm -f cinderace.qcow2
```

---

## Phase 2: Save state that is not backed up

**Where:** Arch, bash.

### 2.1 Git repositories

```bash
for d in ~/Developer/*/ ~/nix; do
  printf '%-32s ' "$d"; git -C "$d" status -sb | head -1
done
```

On 2026-09-24, `learn-clojure` was ahead 1 and `marlin` had no upstream. For
each repository that is ahead: `git -C <dir> push` (touch). Repositories that
cannot be pushed are still carried in the home archive.

**Checkpoint:** every repository you care about shows `...origin/<branch>`
without `ahead`.

### 2.2 Syncthing

Open `http://127.0.0.1:8384`.

**Checkpoint:** the `Cloud` folder is **Up to Date** and every remote device
shows **Up to Date** or **Disconnected** with no pending changes from this
machine.

### 2.3 Final Borg backup

```bash
borgmatic create --verbosity 1 --stats
borgmatic repo-list --last 3
```

**Checkpoint:** the newest archive is `home-cinderance-<today>`. Archives keep
the old hostname; the new system writes `home-cinderace-*` and prunes only
those.

### 2.4 LUKS unlock methods

```bash
LUKS=/dev/disk/by-partuuid/a657bd8b-27fe-4dc7-8d93-520caa984b3c
sudo systemd-cryptenroll "$LUKS"          # (touch) for sudo
```

**Checkpoint:** the list shows a `password` slot, a `recovery` slot (if one
was enrolled) and two `fido2` slots.

Test each typed secret. Each command prompts once:

```bash
sudo cryptsetup open --test-passphrase "$LUKS" && echo PASSPHRASE-OK    # type the passphrase
sudo cryptsetup open --test-passphrase "$LUKS" && echo RECOVERY-OK      # type the recovery key
```

**Checkpoint:** both print `...-OK`. **Stop if either fails**: the installer
unlocks the disk with a typed secret, not a YubiKey.

The FIDO2 enrollments are non-resident: the credential is stored in the LUKS
header, which is kept, so nothing on the YubiKeys changes.

### 2.5 Secure Boot state

```bash
sudo sbctl status
sudo ls -la /var/lib/sbctl/keys
```

**Checkpoint:** `Secure Boot: ✓ Enabled`, `Setup Mode: ✓ Disabled`, and
`keys/` contains `PK`, `KEK` and `db`. These keys are copied to NixOS in
Phase 5, and lanzaboote signs with them; firmware is not re-enrolled.

---

## Phase 3: YubiKey PIV identities and the paper key

**Where:** Arch, bash, inside `nix develop ~/nix`.

agenix encrypts every secret to these recipients:

| Recipient | Decrypts when |
| --- | --- |
| cinderace host SSH key | At every boot and switch, without interaction |
| Primary YubiKey, PIV slot 1 | Editing or rekeying secrets (touch) |
| Backup YubiKey, PIV slot 1 | Same, when the primary is unavailable |
| Paper age key | Recovery when both YubiKeys are unavailable |

PIV is a separate applet from FIDO2: this phase does not change SSH, sudo,
the lock screen or LUKS. The PIV PIN is separate from the FIDO2 PIN.

```bash
nix develop ~/nix
```

### 3.1 Primary key

Insert **only** the primary YubiKey.

```bash
ykman list --serials            # expect exactly: 20477902
ykman piv info | head -8        # PIN tries remaining: 3; no slot 82 (RETIRED1) in use
age-plugin-yubikey --generate --serial 20477902 --slot 1 \
  --name cinderace-primary --pin-policy once --touch-policy cached
```

The PIV PIN is still the factory default, so the command asks for a new PIN
(6–8 characters). It sets the PUK to the same value and stores a random
management key protected by the PIN. Record the PIN in Bitwarden as
`YubiKey 20477902 PIV PIN`. Touch the key when it blinks.

**Checkpoint:** the output ends with a recipient starting `age1yubikey1`.

### 3.2 Backup key

Remove the primary and insert **only** the backup YubiKey.

```bash
ykman list --serials            # expect exactly: 20477782
ykman piv info | head -8
age-plugin-yubikey --generate --serial 20477782 --slot 1 \
  --name cinderace-backup --pin-policy once --touch-policy cached
```

Record the PIN as `YubiKey 20477782 PIV PIN`.

`--touch-policy cached` means one touch covers 15 seconds, so rekeying many
files needs one touch rather than one per file.

### 3.3 Identity stubs and recipients

The stubs are not secret; they tell `age` which YubiKey and slot to use.

```bash
mkdir -p ~/.config/age
: > ~/.config/age/yubikeys.txt
for s in 20477902 20477782; do
  echo "Insert only YubiKey $s, then press Enter"; read -r
  age-plugin-yubikey --identity --serial "$s" --slot 1 >> ~/.config/age/yubikeys.txt
done
grep -o 'age1yubikey1[0-9a-z]*' ~/.config/age/yubikeys.txt
```

**Checkpoint:** two different `age1yubikey1…` strings are printed. Keep this
terminal open; they are needed in Phase 4.

### 3.4 Paper key

```bash
age-keygen -o ~/paper-age.key
cat ~/paper-age.key
```

1. Write down or print the `AGE-SECRET-KEY-1…` line. Store it with the LUKS
   recovery key.
2. Copy the `# public key: age1…` value for Phase 4.
3. Delete the file:

```bash
shred -u ~/paper-age.key
```

**Checkpoint:** the paper copy is legible and `~/paper-age.key` no longer
exists.

---

## Phase 4: Host key and secrets

**Where:** Arch, bash, inside `nix develop ~/nix`.

### 4.1 Staging directories

```bash
STAGE=/mnt/Media/nixos-migration
sudo install -d -o evan -g evan -m 700 "$STAGE"
sudo install -d -m 700 /root/migration-system/etc/ssh /root/migration-system/var/lib
```

### 4.2 cinderace's host key

Secrets are encrypted to this key before NixOS exists; Phase 7 places it at
`/etc/ssh/ssh_host_ed25519_key`.

```bash
sudo ssh-keygen -t ed25519 -N '' -C root@cinderace \
  -f /root/migration-system/etc/ssh/ssh_host_ed25519_key
sudo cat /root/migration-system/etc/ssh/ssh_host_ed25519_key.pub
```

### 4.3 Recipients

Edit `~/nix/secrets/secrets.nix` and replace the four placeholders:

| Placeholder | Value |
| --- | --- |
| `age1yubikey1-REPLACE-20477902` | First recipient from 3.3 |
| `age1yubikey1-REPLACE-20477782` | Second recipient from 3.3 |
| `age1-REPLACE-paper` | Paper public key from 3.4 |
| `ssh-ed25519 REPLACE root@cinderace` | Full line printed in 4.2 |

Only public keys belong in this file.

```bash
grep -c REPLACE ~/nix/secrets/secrets.nix     # expect: 0
```

### 4.4 Remove the placeholders

The repository carries unencrypted placeholder `.age` files so the
configuration builds before this phase. agenix cannot edit them.

```bash
cd ~/nix/secrets
rm -f -- *.age cinderace/*.age
umask 077
enc() { EDITOR="cp -- $2" agenix -e "$1"; }
```

`enc <secret> <file>` encrypts `<file>` as `<secret>`: agenix opens the
cleartext with `$EDITOR`, and `cp` fills it from the file. Values never pass
through the command line or shell history.

### 4.5 Encrypt each secret

Run each block from `~/nix/secrets`. Temporary files go to `/tmp` with mode
600 because of `umask 077`, and are shredded immediately.

**Login password** (`evan-password.age`). Use the current password so the
restored GNOME keyring unlocks at login.

```bash
mkpasswd -m yescrypt > /tmp/pw.hash        # type the password twice
enc evan-password.age /tmp/pw.hash
shred -u /tmp/pw.hash
```

**pam-u2f registrations** (`cinderace/u2f-mappings.age`). The registrations
are bound to origin `pam://cinderance`, which the configuration keeps.

```bash
sudo cat /etc/security/yubikey-u2f > /tmp/u2f
enc cinderace/u2f-mappings.age /tmp/u2f
shred -u /tmp/u2f
```

**Borg** (`cinderace/borg-passphrase.age`, `cinderace/borg-ssh-key.age`):

```bash
enc cinderace/borg-passphrase.age ~/.local/share/borgmatic-secrets/repository-passphrase
enc cinderace/borg-ssh-key.age ~/.local/share/borgmatic-secrets/id_ed25519-borgbase
```

**Syncthing identity** (`cinderace/syncthing-cert.age`,
`cinderace/syncthing-key.age`). Keeps device ID `FBEDWXO-…`, so other devices
need no changes.

```bash
enc cinderace/syncthing-cert.age ~/.local/state/syncthing/cert.pem
enc cinderace/syncthing-key.age ~/.local/state/syncthing/key.pem
```

**ListenBrainz token** (`listenbrainz-token.age`):

```bash
enc listenbrainz-token.age ~/.config/listenbrainz-mpd/token
```

**Lidarr API key** (`cinderace/lidarr.env.age`). Keeping the key keeps
Soularr's and the recommendations job's access valid.

```bash
printf 'LIDARR__AUTH__APIKEY=%s\n' \
  "$(grep -oP '(?<=<ApiKey>)[^<]+' ~/.local/share/media-stack/lidarr/config.xml)" > /tmp/lidarr.env
wc -c /tmp/lidarr.env                          # expect: 54
enc cinderace/lidarr.env.age /tmp/lidarr.env
shred -u /tmp/lidarr.env
```

**slskd credentials** (`cinderace/slskd.env.age`):

```bash
F=~/.local/share/media-stack/slskd/slskd.yml
y() { nix run nixpkgs#yq-go -- "$1" "$F"; }
{
  printf 'SLSKD_SLSK_USERNAME=%s\n' "$(y .soulseek.username)"
  printf 'SLSKD_SLSK_PASSWORD=%s\n' "$(y .soulseek.password)"
  printf 'SLSKD_USERNAME=%s\n'      "$(y .web.authentication.username)"
  printf 'SLSKD_PASSWORD=%s\n'      "$(y .web.authentication.password)"
  printf 'SLSKD_API_KEY=%s\n'       "$(y .web.authentication.api_keys.soularr.key)"
} > /tmp/slskd.env
grep -c '=.' /tmp/slskd.env                    # expect: 5 (no empty values)
enc cinderace/slskd.env.age /tmp/slskd.env
shred -u /tmp/slskd.env
```

**Soularr configuration** (`cinderace/soularr-config.age`). Soularr runs in a
container on the host network, so the container hostnames become
`127.0.0.1`. `[Slskd] download_dir = /downloads` stays: it is the
container's mount of `/mnt/Media/Downloads/slskd/complete`.

```bash
sed -e 's|^host_url = http://lidarr:8686|host_url = http://127.0.0.1:8686|' \
    -e 's|^host_url = http://slskd:5030|host_url = http://127.0.0.1:5030|' \
    ~/.local/share/media-stack/soularr/config.ini > /tmp/soularr.ini
grep '^host_url' /tmp/soularr.ini              # expect: both 127.0.0.1
enc cinderace/soularr-config.age /tmp/soularr.ini
shred -u /tmp/soularr.ini
```

### 4.6 Verify and commit

```bash
cd ~/nix/secrets
ls *.age cinderace/*.age | wc -l               # expect: 10
for f in *.age cinderace/*.age; do
  agenix -d "$f" -i ~/.config/age/yubikeys.txt > /dev/null \
    && echo "ok   $f" || echo "FAIL $f"
done                                           # (touch) once for the cached PIV slot
cd ~/nix
nix build .#nixosConfigurations.cinderace.config.system.build.toplevel
git add -A
git commit -m "Add cinderace secrets and recipients"   # (touch)
git push                                                # (touch)
```

**Checkpoint:** 10 files, every line `ok`, the build succeeds and the push
completes. Flakes only see tracked files, so uncommitted secrets would be
missing from the install.

---

## Phase 5: Stage what the installer needs

**Where:** Arch, bash, inside `nix develop ~/nix` (provides `age`; Arch does
not have it). If Phase 4's shell was closed, start it again with
`nix develop ~/nix`.

Choose a **staging passphrase** and store it in Bitwarden as
`cinderace staging`. It protects the three archives below and is typed on the
installer.

```bash
STAGE=/mnt/Media/nixos-migration
```

### 5.1 System archive

Contents: host key, Secure Boot keys, Tailscale node identity, Bluetooth
pairings (same adapter, same MAC).

```bash
sudo cp -a /var/lib/sbctl /var/lib/tailscale /var/lib/bluetooth /root/migration-system/var/lib/
sudo tar -C /root/migration-system -cpf - . | zstd -T0 | age -p -o "$STAGE/system.tar.zst.age"
```

### 5.2 LUKS header backup

```bash
sudo cryptsetup luksHeaderBackup /dev/disk/by-partuuid/a657bd8b-27fe-4dc7-8d93-520caa984b3c \
  --header-backup-file /root/luks-header.img
sudo cat /root/luks-header.img | age -p -o "$STAGE/luks-header.img.age"
sudo shred -u /root/luks-header.img
```

Keep `luks-header.img.age` permanently, stored with the paper key. It restores
the header, including all keyslots, if the header is ever damaged.

### 5.3 Home archive

Stop the media containers so Lidarr's database is copied consistently. They
stay stopped until the wipe.

```bash
systemctl --user stop soularr slskd lidarr
```

Excluded because they are re-downloaded or regenerated: caches, Unsloth,
World of Warcraft game data, Steam game files, Podman image storage and Lidarr
cover art.

```bash
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

A plain clone the installer can read without network credentials:

```bash
git clone --no-local ~/nix "$STAGE/nix"
```

### 5.5 Verify the staging

```bash
ls -lh "$STAGE"
age -d "$STAGE/system.tar.zst.age" | zstd -d | tar -tf - | grep -E 'ssh_host_ed25519_key$|sbctl/keys/db/'
age -d "$STAGE/home.tar.zst.age" | zstd -d | tar -tf - | grep -cE '^evan/'
git -C "$STAGE/nix" log --oneline -1
sudo rm -rf /root/migration-system
```

**Checkpoint:**

- `system.tar.zst.age` lists `./etc/ssh/ssh_host_ed25519_key` and entries
  under `./var/lib/sbctl/keys/db/`.
- `home.tar.zst.age` decrypts and prints a count over 100,000.
- The clone's last commit is `Add cinderace secrets and recipients`.
- `home.tar.zst.age` is roughly 10–15 GB.

### 5.6 Installer USB

```bash
cd ~/Downloads
curl -LO https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-x86_64-linux.iso
curl -LO https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-x86_64-linux.iso.sha256
echo "expected: $(cut -d' ' -f1 latest-nixos-minimal-x86_64-linux.iso.sha256)"
echo "actual:   $(sha256sum latest-nixos-minimal-x86_64-linux.iso | cut -d' ' -f1)"
```

**Checkpoint:** the two hashes are identical.

Insert the USB stick, then identify it. The stick is the only entry beginning
`usb-`; use the whole-disk entry (no `-partN` suffix):

```bash
ls -l /dev/disk/by-id/ | grep usb-
USB=/dev/disk/by-id/<usb-…-0:0>
lsblk -o NAME,SIZE,MODEL,TRAN "$(readlink -f "$USB")"      # confirm TRAN is usb and the size matches
sudo dd if=latest-nixos-minimal-x86_64-linux.iso of="$USB" bs=4M status=progress oflag=sync
```

**Checkpoint:** `dd` finishes without errors.

---

## Phase 6: Firmware

**Where:** Arch, then the ASRock UEFI setup.

The installer ISO is not signed with your keys, so Secure Boot is turned off
for the install. **Turn it off; do not clear keys.**

```bash
systemctl reboot --firmware-setup
```

In the UEFI, under **Security → Secure Boot**:

1. Set **Secure Boot** to **Disabled**.
2. Do **not** select "Reset to Setup Mode", "Clear Secure Boot Keys",
   "Restore Factory Keys" or "Delete all keys".
3. Save and exit (F10).
4. Open the boot override menu (F11 during POST) and choose the **UEFI** entry
   for the USB stick.

**Checkpoint:** the NixOS installer reaches a root-capable shell prompt
(`[nixos@nixos:~]$`).

---

## Phase 7: Install

**Where:** NixOS installer console.

```bash
sudo -i
```

### 7.1 Network and variables

```bash
ping -c 3 cache.nixos.org

LUKS=/dev/disk/by-partuuid/a657bd8b-27fe-4dc7-8d93-520caa984b3c
ESP=/dev/disk/by-partuuid/15eb8d56-918f-4388-8647-0c4a9a3ad9db
MEDIA=/dev/disk/by-uuid/79cdba09-88c5-4f14-901b-11731d773abe
STAGE=/media-staging/nixos-migration
lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL "$(readlink -f "$LUKS")" "$(readlink -f "$ESP")" "$(readlink -f "$MEDIA")"
```

**Checkpoint:** `ping` gets replies, and:

- `LUKS` is `crypto_LUKS`, about 1.8T.
- `ESP` is `vfat`, label `ARCH_EFI`, about 2G, on the same disk as `LUKS`.
- `MEDIA` is `ext4`, label `Media`, about 3.6T.

If any line differs, stop.

### 7.2 Staging drive and repository

The install runs from a root-owned copy of the repository, which avoids git
ownership errors. The configuration never needs the private Berkeley Mono
repository here; only the home configuration uses it.

```bash
mkdir -p /media-staging
mount -o ro "$MEDIA" /media-staging
cp -r "$STAGE/nix" /root/nix
nix-shell -p git --run 'git -C /root/nix log --oneline -1'
```

**Checkpoint:** the last commit is `Add cinderace secrets and recipients`.

### 7.3 Unlock

```bash
cryptsetup open "$LUKS" cryptroot          # type the LUKS passphrase
ls -l /dev/mapper/cryptroot
```

### 7.4 Wipe, then format and mount with disko

**Point of no return: this destroys Arch and the old home.**

`wipefs` removes the old btrfs and ESP filesystem signatures. disko then
creates everything in `modules/hosts/cinderace/disko.nix` that is missing. It
adopts the existing partitions and the open LUKS container: no `luksFormat`,
and the partition table keeps its layout and GUIDs.
`checks.x86_64-linux.cinderace-disko-adopt` tests this exact sequence.

```bash
wipefs -a /dev/mapper/cryptroot
wipefs -a "$ESP"
nix --extra-experimental-features 'nix-command flakes' \
  run --inputs-from /root/nix disko -- --mode format,mount --flake /root/nix#cinderace
findmnt -R /mnt
```

disko prints `Error encountered; not saving changes.` twice. That is `sgdisk`
refusing to create partitions that already exist; disko then only sets their
names and types.

**Checkpoint:** `findmnt` shows `/mnt`, `/mnt/home`, `/mnt/home/.snapshots`,
`/mnt/nix` and `/mnt/var/log` on `/dev/mapper/cryptroot`, and `/mnt/boot` as
vfat.

### 7.5 Restore host key, Secure Boot keys and device state

```bash
nix-shell -p age zstd --run \
  "age -d $STAGE/system.tar.zst.age | zstd -d | tar -xpf - --numeric-owner -C /mnt"
ls -l /mnt/etc/ssh/ssh_host_ed25519_key
ls /mnt/var/lib/sbctl/keys
```

Confirm the restored host key is the one the secrets are encrypted to:

```bash
ssh-keygen -y -f /mnt/etc/ssh/ssh_host_ed25519_key | cut -d' ' -f2
grep -o 'ssh-ed25519 [A-Za-z0-9+/=]*' /root/nix/secrets/secrets.nix | cut -d' ' -f2
```

**Checkpoint:** the host key is `-rw------- 1 root root`, `keys/` contains
`PK KEK db`, and the two printed keys are identical. If they differ, stop:
the installed system would not be able to decrypt any secret.

### 7.6 Install NixOS

```bash
nixos-install --root /mnt --flake /root/nix#cinderace --no-root-passwd \
  --option experimental-features 'nix-command flakes'
```

This downloads and builds the system, then installs lanzaboote and signs the
boot files with the restored keys.

**Checkpoint:** the output ends with `installation finished!`. If the
bootloader step fails, see [lanzaboote fails during install](#lanzaboote-fails-during-install).

### 7.7 Verify the boot files

```bash
nixos-enter --root /mnt -c 'sbctl verify'
ls /mnt/boot/EFI/Linux /mnt/boot/EFI/systemd
efibootmgr -v
```

**Checkpoint:**

- `sbctl verify` marks `systemd-bootx64.efi`, `BOOTX64.EFI` and every
  `nixos-generation-*.efi` as signed.
- `efibootmgr` has a `Linux Boot Manager` entry pointing to
  `\EFI\systemd\systemd-bootx64.efi`.

Remove stale Arch entries (for example direct-UKI entries) by number:

```bash
efibootmgr -b <XXXX> -B
```

### 7.8 Home directory, repository and Arch home

```bash
install -d -o 1000 -g 1000 -m 700 /mnt/home/evan
cp -a "$STAGE/nix" /mnt/home/evan/nix
chown -R 1000:1000 /mnt/home/evan/nix

install -d -o 1000 -g 1000 -m 700 /mnt/home/evan/.arch-home
nix-shell -p age zstd --run \
  "age -d $STAGE/home.tar.zst.age | zstd -d | tar -xpf - --numeric-owner -C /mnt/home/evan/.arch-home"
ls /mnt/home/evan/.arch-home/evan | head
```

**Checkpoint:** the listing shows the old home (`Developer`, `sync`, …).

### 7.9 Unmount and reboot

```bash
umount /media-staging
umount -R /mnt
cryptsetup close cryptroot
reboot
```

Remove the USB stick while the firmware logo shows.

---

## Phase 8: First boot and user environment

**Where:** cinderace. Secure Boot is still off.

### 8.1 Unlock

Plymouth shows the Lone animation and a message asking to confirm presence on
the security token. Touch either YubiKey.

**Checkpoint:** boot continues to GDM. If only a passphrase prompt appears,
type the passphrase and see [No FIDO2 prompt](#no-fido2-prompt-at-boot).

### 8.2 Restore user data from a text console

**Do not log in at GDM yet.** Applications create fresh copies of the GNOME
keyring, fish history and browser profiles on first use, which would then win
over the restored ones. The home-manager configuration does not exist yet
either.

Press **Ctrl+Alt+F3** and log in as `evan` with the password.

```bash
bash
A=~/.arch-home/evan
sudo systemctl stop syncthing                   # (touch); prevents it from writing ~/sync meanwhile
for p in .ssh sync Developer Pictures Downloads \
         .local/share/keyrings .local/share/fish/fish_history \
         .config/mozilla .config/BraveSoftware .local/share/qutebrowser \
         .local/state/yubikey-setup; do
  mkdir -p "$(dirname ~/"$p")"
  rsync -a "$A/$p" "$(dirname ~/"$p")/"
done
chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_*
sudo systemctl start syncthing
```

| Path | Contents |
| --- | --- |
| `.ssh` | FIDO2 SSH handles for both YubiKeys, `known_hosts`, software keys |
| `sync` | Syncthing folder; restoring it avoids a full resync |
| `.local/share/keyrings` | GNOME keyring; unlocks at login with the unchanged password |
| `.config/mozilla` | Firefox profile `b437d468.default-release` |

### 8.3 Activate home-manager

The home configuration fetches Berkeley Mono from the private
`evanriley/berkeley-mono` repository over SSH; the YubiKey SSH handles
restored in 8.2 make that possible.

```bash
cd ~/nix
nh home switch -b hm-backup                     # (touch) when fetching berkeley-mono
```

`-b hm-backup` renames existing files that home-manager replaces (for example
the restored `~/.ssh/config` and Firefox's `profiles.ini`) to `*.hm-backup`.

**Checkpoint:** the switch ends without errors; `ls ~/.config/niri` shows
`config.kdl`.

```bash
exit          # leave bash
exit          # log out of the console
```

Press **Ctrl+Alt+F1** to return to GDM.

### 8.4 First graphical login

Log in as `evan` with the password.

**Checkpoint:**

- niri starts with Waybar hidden (toggle: Mod+Ctrl+B), Steam and Discord
  launching in the background.
- `sudo true` in foot succeeds after a touch, without a password.
- `ls ~/.local/share/keyrings` lists `login.keyring`, and opening Brave
  does not ask for a keyring password.

### 8.5 Re-enable Secure Boot

```bash
systemctl reboot --firmware-setup
```

**Security → Secure Boot → Enabled**, then save and exit. Unlock with a touch
as in 8.1 and log in.

```bash
bootctl status | grep -i 'secure boot'          # expect: enabled (user)
sudo sbctl status                               # expect: Secure Boot ✓ Enabled
```

### 8.6 System checks

```bash
sudo ls /run/agenix                             # 10 entries
systemctl --failed                              # expect: 0 loaded units listed
systemctl --user --failed                       # expect: 0 loaded units listed
systemctl --user is-active waybar swaync swayosd darkman display-mode swayidle yubikey-touch-detector scapectl
systemctl is-active lidarr slskd podman-soularr syncthing tailscaled
ssh -T git@github.com                           # (touch) expect: Hi evanriley!
```

Signing test:

```bash
T=$(mktemp -d) && git -C "$T" init -q \
  && git -C "$T" commit -q --allow-empty -m "signing test" \
  && git -C "$T" log --show-signature -1; rm -rf "$T"   # (touch) expect: Good "git" signature
```

**Checkpoint:** every command produces the expected result, and every unit
reports `active`.

### 8.7 Desktop checks

- [ ] **Lock:** Mod+Alt+L locks; touching a YubiKey unlocks. With both keys
      removed, the password unlocks.
- [ ] **Idle:** after 5 minutes the screen locks, after 10 the monitor turns
      off, after 30 the system suspends. The Waybar sleep toggle blocks the
      suspend step only.
- [ ] **Theme:** `darkman set light` then `darkman set dark` switch foot,
      niri borders, Waybar, GTK apps and running nvim within a few seconds.
- [ ] **Display modes:** switch the monitor to 3K; `display-mode` sets
      3072×1728 at 330 Hz, scale 1. Switch back to 6K before rebooting.
- [ ] **Audio:** sound on the DX5; powering the Scape headset on switches the
      default sink to it, and off switches back.
- [ ] **Bluetooth:** paired devices reconnect without re-pairing.
- [ ] **Portals:** screen sharing in Firefox and the file picker work.
- [ ] **Tailscale:** `tailscale status` shows the node logged in with its old
      name.
- [ ] **Syncthing:** `http://127.0.0.1:8384` shows device ID `FBEDWXO-…` and
      the `Cloud` folder Up to Date.
- [ ] **Firefox:** existing profile loads; the 13 policy extensions are
      present; `about:policies` lists DisableTelemetry, DisableFirefoxStudies
      and ExtensionSettings as active.
- [ ] **Folders:** `xdg-user-dir PICTURES` prints `/home/evan/Pictures` and
      `xdg-user-dir SCREENSHOTS` prints `/home/evan/Pictures/Screenshots`.

---

## Phase 9: Services, games and backups

**Where:** cinderace, bash as evan.

```bash
bash
A=~/.arch-home/evan
```

### 9.1 Media library permissions

The media services run as their own users in the `media` group:

```bash
sudo chgrp -R media /mnt/Media/Music /mnt/Media/Downloads
sudo chmod -R g+rwX /mnt/Media/Music /mnt/Media/Downloads
sudo find /mnt/Media/Music /mnt/Media/Downloads -type d -exec chmod g+s {} +
```

### 9.2 Lidarr

```bash
sudo systemctl stop lidarr
sudo rsync -a --exclude logs --exclude 'logs.db*' \
  "$A/.local/share/media-stack/lidarr/" /var/lib/lidarr/
sudo chown -R lidarr:media /var/lib/lidarr
sudo systemctl start lidarr
```

Open `http://127.0.0.1:8686`.

**Checkpoint:** artists are present; **System → Status** shows no root folder
errors for `/data/Music`; cover art re-downloads over the next hour.

### 9.3 slskd, Soularr and the recommendations cache

```bash
sudo systemctl stop slskd
sudo rsync -a "$A/.local/share/media-stack/slskd/data/" /var/lib/slskd/data/
sudo chown -R slskd:media /var/lib/slskd
sudo systemctl start slskd

sudo cp "$A/.local/share/media-stack/soularr/failed_imports.json" /var/lib/soularr/
sudo systemctl restart podman-soularr

sudo install -d /var/lib/private/listenbrainz-recommendations
sudo cp "$A/.local/state/arch-switch/listenbrainz-release-groups.json" \
  /var/lib/private/listenbrainz-recommendations/
```

**Checkpoint:** `http://127.0.0.1:5030` logs in with the old web credentials
and shows the Soulseek connection; `journalctl -u podman-soularr -n 20` shows
Soularr polling Lidarr without authentication errors.

### 9.4 Music

```bash
systemctl --user is-active mpd mpd-mpris listenbrainz-mpd
```

**Checkpoint:** all three are `active`; Mod+Ctrl+R opens rmpc and plays.

### 9.5 Games

1. Steam: **Settings → Storage → Add Drive → `/mnt/Games/SteamLibrary`**.
   GE-Proton is provided by Nix and appears under a game's
   **Properties → Compatibility**. For GameMode, set a game's launch options
   to `gamemoderun %command%`; `gamemoded -s` shows whether it is active.
2. World of Warcraft: install Battle.net through Faugus, install WoW, then
   before the first launch:

```bash
WOW="Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_retail_"
rsync -a "$A/$WOW/WTF/" ~/"$WOW/WTF/"
```

### 9.6 Backups

```bash
sudo systemctl start borgmatic.service
journalctl -u borgmatic -f                      # Ctrl+C when it finishes
```

The first run rebuilds Borg's cache under `/root/.cache/borg` and takes
longer than later runs.

```bash
sudo borgmatic repo-list --last 2
sudo snapper -c home list | tail -3
```

**Checkpoint:** a `home-cinderace-*` archive exists alongside the untouched
`home-cinderance-*` archives, and Snapper lists timeline snapshots of `/home`.

---

## Phase 10: Cleanup

**Where:** cinderace, after about 30 days without needing anything from
`~/.arch-home`.

```bash
cp /mnt/Media/nixos-migration/luks-header.img.age <permanent location>
rm -rf ~/.arch-home
sudo rm -rf /mnt/Media/nixos-migration
find ~ -name '*.hm-backup'                      # inspect, then delete
```

Also:

- Remove `~/sync/dotfiles` and `~/sync/arch-switch` from the Syncthing folder;
  archive the GitHub `dotfiles` repository.
- Old `home-cinderance-*` Borg archives are never pruned automatically; delete
  them with `borg delete` once they are no longer wanted.

---

## Troubleshooting

### No FIDO2 prompt at boot

Type the passphrase to boot. Then:

```bash
sudo systemd-cryptenroll /dev/disk/by-partuuid/a657bd8b-27fe-4dc7-8d93-520caa984b3c
nix eval ~/nix#nixosConfigurations.cinderace.config.boot.initrd.luks.devices.cryptroot.crypttabExtraOpts
nix eval ~/nix#nixosConfigurations.cinderace.config.boot.initrd.systemd.enable
```

Both `fido2` slots must be listed, the first `nix eval` must print
`[ "fido2-device=auto" ]` and the second `true`. Fix
`modules/hosts/cinderace/disko.nix` or `modules/system/boot.nix` if not, then
`nh os switch` and reboot.

### lanzaboote fails during install

In `/root/nix/modules/hosts/cinderace/configuration.nix`, remove
`secure-boot` from the NixOS imports and commit. Re-run 7.6, boot with Secure
Boot off, restore the import, `nh os switch`, check `sudo sbctl verify`, then
enable Secure Boot as in 8.5.

### Secure Boot violation after enabling it

Disable Secure Boot in firmware and boot. `sudo sbctl verify` listing
unsigned files means the keys in `/var/lib/sbctl` were not restored or differ
from firmware. `sudo sbctl status` showing Setup Mode means the firmware keys
were cleared; re-enroll with `sudo sbctl enroll-keys --microsoft`.

### Password rejected at login

The password secret did not decrypt. `users.mutableUsers = false`, so
`passwd` changes are overwritten on activation.

1. Boot the installer and run 7.1, 7.2 and 7.3.
2. Mount with
   `nix --extra-experimental-features 'nix-command flakes' run --inputs-from /root/nix disko -- --mode mount --flake /root/nix#cinderace`.
3. In `/root/nix/modules/system/users.nix`, replace `hashedPasswordFile = …`
   with `hashedPassword = "<output of mkpasswd -m yescrypt>";` and commit.
4. Re-run 7.6 and reboot.
5. Compare `/etc/ssh/ssh_host_ed25519_key.pub` with `hosts.cinderace` in
   `secrets/secrets.nix`; fix, `agenix -r`, and revert step 3.

### `nh home switch` cannot fetch berkeley-mono

`~/.ssh` is missing or the YubiKey was not touched. Check
`ssh -T git@github.com` (touch). Without SSH access, activate once without the
font by building on another machine, or temporarily point the `berkeley-mono`
input at a local copy of the fonts:
`nh home switch -b hm-backup --override-input berkeley-mono path:<dir>`,
where `<dir>` contains a `fonts/` directory with the TTF files.

### Theme does not switch

`systemctl --user status darkman` must be active. Run
`apply-theme light` / `apply-theme dark` directly; errors print to the
terminal. `ls -l ~/.local/state/theme/base` must point to a
`home-manager-generation`; if not, run `nh home switch` once.

### Recovery without Arch

There is no Arch installation to fall back to. Repairs go through the
installer USB and `nixos-enter`. Data is in Borg (`home-cinderance-*` and
`home-cinderace-*`) and, until Phase 10, in `/mnt/Media/nixos-migration`. The
last Arch Borg archive contains `/var/lib/system-recovery/system-config.tar`
with the old `/etc`.
