# nix

NixOS and nix-darwin configurations for my machines. They live in the
[`maybe` monorepo](../README.md) at `nix/` and are mirrored read-only to
[GitHub](https://github.com/evanriley/nix). They depend on private inputs and
secrets, so they won't build as-is elsewhere.

This is a personal project, source available under the [MIT License](LICENSE).
It takes no outside contributions, and the mirror takes no issues or pull
requests. Report a serious problem, such as a security hole, by email to
[evan@evanriley.com](mailto:evan@evanriley.com).

| Host | Hardware | System | Status |
| --- | --- | --- | --- |
| `cinderace` | Desktop: Ryzen 7 9800X3D, Radeon RX 9070 XT | NixOS, x86_64-linux | Active |
| `ninetales` | MacBook Pro, M1 Pro | nix-darwin, aarch64-darwin | Active |
| `blaziken` | Server: OVH KS-5, Xeon E3-1270 v6, 32 GB | NixOS, x86_64-linux | Active |
| `ci-builder` | GCE Spot VM, c4d-highcpu-16 or c3d-highcpu-30 | NixOS, x86_64-linux | Active |

## Usage

```sh
git clone ssh://evan@git.maybemaybe.lol:29418/maybe ~/maybe
```

The flake is in `~/maybe/nix`. The root README covers the
[Gerrit workflow](../README.md) for contributing changes.

| | cinderace | ninetales |
| --- | --- | --- |
| Apply system | `nh os switch` | `nh darwin switch` |
| Apply home | `nh home switch` | `nh home switch` |
| Build only | `nh os build`, `nh home build` | `nh darwin build`, `nh home build` |
| Roll back system | `nh os rollback` | `sudo darwin-rebuild --rollback` |
| Roll back home | `home-manager generations`, then `<path>/activate` | `home-manager generations`, then `<path>/activate` |

blaziken has no Home Manager configuration. Deploy it from any host with SSH
access over Tailscale, using [deploy-rs](https://github.com/serokell/deploy-rs)
from the dev shell:

```sh
cd ~/maybe/nix && nix develop -c deploy .#blaziken
```

deploy-rs rolls back automatically when the activation fails. Build without
deploying:

```sh
nix build ~/maybe/nix#nixosConfigurations.blaziken.config.system.build.toplevel
```

Update inputs with `nix flake update --flake ~/maybe/nix`; `berkeley-mono`,
`monobiome` and `lanzaboote` are updated by hand.

CI runs on [Buildkite](https://buildkite.com/riley-industries/maybe) on the
`blaziken` agents and builds what changed in `legacyPackages.x86_64-linux.ci`
([how the pipeline works](../README.md#ci)): the flake checks, the
cinderace, blaziken and ci-builder toplevels, and an evaluation of the home
configurations and of ninetales, which cannot be built on x86_64-linux. The
toplevels are pushed to the `evanriley` cachix so switches substitute from it.

After a bad update, restore the previous lock and switch again:

```sh
git -C ~/maybe checkout HEAD~1 -- nix/flake.lock
```

`nh home switch` needs GitHub SSH access to fetch the private
`evanriley/berkeley-mono` input; `orca` and `manta` live in the monorepo.

### Remote work

ninetales works on cinderace over the tailnet. cinderace runs sshd (key-only,
ed25519 host key) and Eternal Terminal on port 2022, both opened on
`tailscale0` only. Tailscale SSH is off (`--ssh=false`). ninetales pins
cinderace's host key from `meta.hostKeys.cinderace` in
`/etc/ssh/ssh_known_hosts`.

`ssh cinderace` shares one connection for 10 minutes after the last session
closes (ControlMaster). Close it early:

```sh
ssh -O exit cinderace
```

`et cinderace` opens a session that survives sleep and network changes; `t`
then attaches tmux.

Copying in tmux (copy mode `y`) or in nvim inside tmux goes to the clipboard
of the attached terminal through OSC 52. nvim's `p` inside tmux reads that
clipboard; Ghostty allows the read without a prompt
(`clipboard-read = allow`).

### Secrets

Secrets are [agenix](https://github.com/ryantm/agenix) files in `secrets/`,
decrypted at boot with each host's SSH key. Editing needs a YubiKey; the paper
key is the recovery recipient.

Edit a secret:

```sh
cd ~/maybe/nix/secrets
nix develop ~/maybe/nix -c agenix -e <path>.age -i ~/.config/age/yubikeys.txt
```

Add a secret:

1. Add it to `secrets/secrets.nix`: `hostSecrets "<host>" [ "<name>.age" ]` for one
   host, or `shared [ "<host>" … ] "<name>.age"` for several.
2. Create it with the edit command above.
3. Declare it: `age.secrets.<name>.file = inputs.self + "/secrets/<path>.age";`
4. `git add` the `.age` file and switch.

After changing recipients in `secrets/secrets.nix`, rekey:

```sh
cd ~/maybe/nix/secrets
nix develop ~/maybe/nix -c agenix -r -i ~/.config/age/yubikeys.txt
```

### Shell history

[Atuin](https://atuin.sh) syncs shell history between hosts, encrypted with
`secrets/atuin-key.age`, which every host in `hosts` in `secrets/secrets.nix`
decrypts. Log in once per host:

```sh
atuin login -u <username>
```

## blaziken

A headless server, updated with deploy-rs. It has
key-only SSH and is administered over Tailscale. Its disks are an mdadm RAID1
pair (`disko.nix`) with GRUB on both. It imports `nixos.server` and
`nixos.backup`; secrets are in `secrets/blaziken/`.

| Service | Address | Module in `modules/hosts/blaziken/` |
| --- | --- | --- |
| nginx, wildcard ACME cert | `*.maybemaybe.lol` | `nginx.nix` |
| Homepage behind Anubis | `maybemaybe.lol` | `homepage/` |
| Gerrit behind Anubis, Pocket ID login | `git.maybemaybe.lol` | `gerrit.nix` |
| cgit behind Anubis | `code.maybemaybe.lol` | `gerrit.nix` |
| zoekt code search behind Anubis | `cs.maybemaybe.lol` | `code-search.nix` |
| git-bug read-only web UI behind Anubis | `bugs.maybemaybe.lol` | `git-bug.nix` |
| git-bug web UI behind Anubis, Pocket ID login | `bugs-edit.maybemaybe.lol` | `git-bug.nix` |
| Pocket ID (OIDC provider) | `id.maybemaybe.lol` | `pocket-id.nix` |
| Change short links | `cl.maybemaybe.lol/<n>` | `gerrit.nix` |
| Bug short links | `b.maybemaybe.lol/<id>` | `git-bug.nix` |
| Other subdomains redirect home | `*.maybemaybe.lol` | `nginx.nix` |
| Buildkite agents (two) | queue `blaziken` | `buildkite.nix` |
| Gerrit-to-Buildkite webhook | local | `ci-trigger.nix` |
| Spot builder launcher | GCE, queue `spot-builders` | `ci-spot-poller.nix` |
| Fallback Buildkite agent, on demand | queue `spot-builders` | `buildkite.nix` |
| Borg backups | BorgBase | `backup.nix` |
| RAID, disk and service alerts | healthchecks.io | `monitoring.nix` |

### Gerrit state outside Nix

Gerrit keeps its project and access configuration in git, on
`refs/meta/config` of each repository, not in this flake. The Borg bundles
(see [Gerrit](#gerrit)) restore it; a Gerrit set up from scratch needs it
recreated by hand. CI depends on:

- `maybe`, `webhooks.config`: remote `buildkite` posts `patchset-created` and
  `ref-updated` to `http://127.0.0.1:8470/gerrit` (`ci-trigger.nix`).
- `maybe`, `project.config`: `submit.action = fast forward only`; access is
  inherited from All-Projects.
- All-Projects, `project.config`:
  - The `Verified` label (-1..+1) and its submit requirement, which does not
    apply to `refs/meta/config`.
  - `label-Verified = -1..+1 group CI` on `refs/heads/*`.
  - `read = group Anonymous Users` on `refs/heads/*`, which makes the
    repository public.
  - No `push` on `refs/heads/*`; changes reach `main` only by submit.
- Groups: `buildkite` in CI; `evan` in Administrators.

Read or edit a project's configuration:

```sh
git fetch ssh://evan@git.maybemaybe.lol:29418/<project> refs/meta/config
git checkout FETCH_HEAD
git push ssh://evan@git.maybemaybe.lol:29418/<project> HEAD:refs/for/refs/meta/config
```

The Access page in the web UI edits the same files.

### Pocket ID setup

Pocket ID is the OIDC identity provider at `id.maybemaybe.lol`. Its
encryption key is `secrets/blaziken/pocket-id-key.age`; users, passkeys and
OIDC clients live in its SQLite database, not in this flake. nginx answers
404 to its first-run signup request (`/api/signup/setup`), because until the
first user exists that request makes any caller an admin. To set up an empty
database, remove that location in `pocket-id.nix`, deploy, create the admin
user and passkey at [the setup page](https://id.maybemaybe.lol/setup) at once,
then restore the location and deploy again.

Gerrit logs in through a Pocket ID OIDC client with callback URL
`https://git.maybemaybe.lol/oauth`. `gerrit.nix` sets the client ID; the client
secret is `secrets/blaziken/gerrit-oidc-secret.age`, which Gerrit's `preStart`
writes into `etc/secure.config`. A Pocket ID login maps to a Gerrit account by
the external ID `discovery-oauth:<Pocket ID user ID>`; an account created
before the switch needs that external ID added to `refs/meta/external-ids` in
All-Users before its first Pocket ID login.

The login runs on the gerrit-oauth-provider plugin, vendored as
`modules/hosts/blaziken/gerrit-oauth-provider.jar`: a `stable-3.14` CI build,
because no release of its OIDC discovery provider loads on Gerrit 3.14. When
nixpkgs ships Gerrit 3.15, replace it with the release `oauth-discovery.jar`
for that version and update the hash in `gerrit.nix`.

git-bug editing at `bugs-edit.maybemaybe.lol` sits behind oauth2-proxy, which
logs in through a second Pocket ID OIDC client with callback URL
`https://bugs-edit.maybemaybe.lol/oauth2/callback`. `git-bug.nix` sets the
client ID and admits only `evan@evanriley.com`, whose email must be marked
verified in Pocket ID. The client secret is
`secrets/blaziken/git-bug-oidc-secret.age` and the cookie secret is
`secrets/blaziken/oauth2-proxy-cookie-secret.age`. The read-only instance at
`bugs.maybemaybe.lol` restarts after each sync that pushes new bug refs.

### Spot builders

The `spot-builders` Buildkite queue runs on GCE Spot VMs booted from the
`ci-builder` image. `.buildkite/pipeline.sh` sends big-parallel steps there;
`CI_HEAVY_QUEUE=blaziken` on a manual build keeps them on blaziken.

- `ci-spot-poller.service` on blaziken (`ci-spot-poller.nix`) runs as
  `buildkite-agent-main`. Every 30 seconds it:
  - reads the queue's scheduled jobs and idle agents from the Buildkite agent
    metrics API;
  - launches one VM per unserved job, `c4d-highcpu-16` first and then
    `c3d-highcpu-30`, in `us-central1-a`, `-b`, `-c` and `-f`, keeping at most
    `CI_SPOT_MAX_INSTANCES` (default 3) VMs labelled `maybe-ci=true`;
  - deletes labelled VMs that are stopped, not ready after 15 minutes, or older
    than 6 hours 15 minutes.
- Each VM receives the ci-builder toplevel that `ci.sh publish` last recorded
  in `/var/lib/buildkite-agent-main/ci-builder-system`. Its startup script
  switches to that system, starts one agent and sets the guest attribute
  `ci-builder/ready`. The agent exits after 3 idle minutes and the VM powers
  off; GCE deletes any VM after 6 hours.
- `buildkite-agent-spot-fallback.service` on blaziken serves the same queue as
  the untrusted `buildkite-agent-blaziken` user and never starts at boot.
  While jobs are queued, the poller starts it through `ci-spot-fallback.path`
  when every launch failed with no VM alive, when the ci-builder system file
  is missing or invalid, or when no VM has been ready for 5 minutes. It exits
  after 5 idle minutes.
- `ci-remote-builder` (`ci-remote-builder.nix`) leases a single-use VM as a Nix
  remote builder for publish. It is on the `buildkite-agent-main` job PATH
  only, and `buildkite-agent-main` is a trusted Nix user so the daemon accepts
  its `builders`; the untrusted agents are neither.
  - `ci-remote-builder lease <job-id>` launches `maybe-ci-remote-<job-id>`,
    labelled `maybe-ci-remote=true` and tagged `ci-remote-builder`, with the
    same shapes and zones as the poller and the ci-remote-builder toplevel
    from `/var/lib/buildkite-agent-main/ci-remote-builder-system`. It waits up
    to 5 minutes for the guest attribute `ci-remote-builder/ready` and prints
    one `builders` line for `ssh-ng://builder@<address>`, pinned to the host
    key the VM published in `ci-remote-builder/host-key`. On any failure it
    deletes the VM and exits non-zero.
  - `ci-remote-builder release <job-id>` deletes the VM and succeeds when it is
    already gone.
  - The poller ignores these VMs. GCE deletes each one after 2 hours.
  - `ci.sh publish` leases one when `CI_REMOTE_BUILDER=1` (set by the main
    agent) and `nix build --dry-run` lists derivations to build that require
    only `big-parallel`. It builds the other targets while the lease starts,
    builds those with the VM as a builder, rebuilds a target that failed on it
    locally, and releases it on every exit. A failed lease builds locally.

The poller logs each launch, deletion and fallback request; read them with
`journalctl -u ci-spot-poller`. Until `secrets/blaziken/gcp-ci-key.age` holds
a service-account key, it logs the error and queued jobs run on the fallback
agent.

One-time setup, in a shell with gcloud (`nix shell nixpkgs#google-cloud-sdk`):

1. Create the network, firewall, custom role and service account in a gcloud
   project:

   ```sh
   gcloud config set project <project>
   ~/maybe/nix/gcp/ci-spot.sh
   ```

   The firewall allows egress to TCP 80 and 443 only. The only ingress is TCP
   22 from blaziken (147.135.1.187) to VMs tagged `ci-remote-builder`. Traffic
   to the metadata server at 169.254.169.254, including DNS, is not subject to
   VPC firewall rules.
2. Run the commands the script prints. They create a key for `maybe-ci-spot`,
   encrypt it into `secrets/blaziken/gcp-ci-key.age` and shred the plaintext.
3. Build the image and add it to the `ci-builder` family through a Cloud
   Storage bucket in the project:

   ```sh
   nix build ~/maybe/nix#nixosConfigurations.ci-builder.config.system.build.googleComputeImage -o ci-builder-image
   gcloud storage cp ci-builder-image/*.raw.tar.gz gs://<bucket>/ci-builder.raw.tar.gz
   gcloud compute images create ci-builder-<yyyymmdd> --source-uri=gs://<bucket>/ci-builder.raw.tar.gz --family=ci-builder --guest-os-features=UEFI_COMPATIBLE,GVNIC --storage-location=us-central1
   gcloud storage rm gs://<bucket>/ci-builder.raw.tar.gz
   rm ci-builder-image
   ```

   VMs boot the newest image in the family and then switch to the published
   system, so the image needs a rebuild only when its boot path changes.
4. Create the `spot-builders` queue in the Buildkite cluster.
5. Commit the key and deploy blaziken.

## Adding a host

Profiles in `modules/profiles/`:

| Module | Contents |
| --- | --- |
| `nixos.base`, `darwin.base` | Nix, agenix, user, locale, networking, fish |
| `nixos.server` | Nix, agenix, user, locale, networking, fish, zram |
| `nixos.workstation` | `base` plus boot, zram, NextDNS, YubiKey, noctalia-greeter, umbriel, Plymouth, audio, Bluetooth, fonts |
| `homeManager.cli` | Home basics, dotfiles, shell, Atuin, git, jj, Neovim, theme, agent config |
| `homeManager.workstation` | `cli` plus browsers, Discord, mpv, Bitwarden, YubiKey tools |
| `homeManager.desktop` | `workstation` plus the Linux session, umbriel and desktop apps |

1. Create `modules/hosts/<host>/configuration.nix` with
   `flake.nixosConfigurations.<host>` (or `darwinConfigurations`) and a
   `flake.modules.nixos.<host>` module that imports `base`, `server` or
   `workstation` and the features it needs, and sets `networking.hostName` and
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
5. Add the host to the machine lists in
   `home/config/ai/skills/nix-environment/SKILL.md` and
   `home/config/ai/pi/AGENTS.md`.
6. Add the host to `legacyPackages.ci` in `modules/flake/ci.nix`: `targets`
   for a NixOS host, which CI builds, or `evalOnly` for a darwin host. For a
   server, also add a deploy-rs node in `modules/flake/deploy.nix`.

## First-time setup

### ninetales

1. Install [Lix](https://lix.systems/install/) and [Homebrew](https://brew.sh).
2. Create the host's SSH key, add `~/.ssh/id_ed25519.pub` to GitHub, to
   Gerrit (Settings → SSH Keys) and to `meta.user.sshKeys` in
   `modules/flake/meta.nix` (blaziken and cinderace both read it), then clone:

   ```sh
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C evan@ninetales
   git clone ssh://evan@git.maybemaybe.lol:29418/maybe ~/maybe
   ```

3. Apply the system, then home:

   ```sh
   sudo nix run --inputs-from ~/maybe/nix nix-darwin -- switch --flake ~/maybe/nix#ninetales
   nix run --inputs-from ~/maybe/nix home-manager -- switch --flake ~/maybe/nix#evan@ninetales
   ```

Then, by hand:

- Grant Accessibility to OmniWM and skhd, and Input Monitoring to OmniWM.
- Tailscale app: allow its VPN configuration, log in, and turn off Use
  Tailscale DNS (NextDNS resolves, forwarding `ts.net` to MagicDNS).
- In Firefox, `about:profiles` → Create a New Profile → Choose Folder
  `~/Library/Application Support/org.nixos.firefox/Profiles/default` → Set as
  default profile.
- System Settings → Spotlight: exclude `~/maybe`.
- If a Dock icon shows `?`, run `killall Dock`.
- Log in to Atuin (see [Shell history](#shell-history)).

### cinderace

1. Boot the NixOS installer, clone with
   `git clone ssh://evan@git.maybemaybe.lol:29418/maybe ~/maybe`, and
   partition and mount the disks with disko.
2. Restore the host SSH key and the Secure Boot keys from Borg into `/mnt`
   (see [Restoring from Borg](#restoring-from-borg)). The agenix secrets,
   including the login password, only decrypt with that host key.

   ```sh
   cd /mnt
   sudo -E nix shell nixpkgs#borgbackup -c borg extract ::<archive> etc/ssh/ssh_host_ed25519_key etc/ssh/ssh_host_ed25519_key.pub var/lib/sbctl
   ```

3. `nixos-install --flake ~/maybe/nix#cinderace`
4. After the first login, log in to Atuin (see
   [Shell history](#shell-history)).

## Restoring from Borg

All three hosts back up daily to BorgBase; `repos` in
`modules/services/backup.nix` maps each host to its repository.

```sh
sudo borgmatic repo-list --last 5
sudo borgmatic extract --archive latest --path <home>/<path> --destination /tmp/restore
```

`<home>` is `home/evan` on cinderace, `Users/evan` on ninetales and
`home/evan` on blaziken.

On a new machine, borgmatic has no credentials yet. The passphrase and the key
export (`borg-key-<host>`) are in Bitwarden; the SSH key decrypts with a
YubiKey:

```sh
cd ~/maybe/nix/secrets
nix develop ~/maybe/nix -c agenix -d <host>/borg-ssh-key.age -i ~/.config/age/yubikeys.txt > /tmp/borg-ssh-key
chmod 600 /tmp/borg-ssh-key
export BORG_RSH="ssh -i /tmp/borg-ssh-key" BORG_REPO="ssh://<repo>@<repo>.repo.borgbase.com/./repo"
nix shell nixpkgs#borgbackup -c borg list
nix shell nixpkgs#borgbackup -c borg extract ::<archive> <path>
```

### Gerrit

blaziken backs up `/var/lib/gerrit` live and, before each run, a
`git bundle --all` of every repository in `/var/backup/gerrit/`. The bundles
are consistent snapshots of all refs: review history (`refs/changes/*`,
NoteDb), bugs (`refs/bugs/*`), accounts (All-Users) and access rules
(All-Projects).

1. Stop Gerrit: `sudo systemctl stop gerrit`.
2. Extract `var/lib/gerrit` and `var/backup/gerrit` from the archive.
3. If a repository in `/var/lib/gerrit/git` is damaged, replace it with a
   mirror of its bundle, owned by `gerrit`:

   ```sh
   sudo -u gerrit git clone --mirror /var/backup/gerrit/<name>.bundle /var/lib/gerrit/git/<name>.git
   ```

4. Rebuild the search index, then start Gerrit:

   ```sh
   sudo -u gerrit $(systemctl show -P ExecStart gerrit | grep -oE '/nix/store/[^ ]+/bin/gerrit' | head -1) reindex -d /var/lib/gerrit
   sudo systemctl start gerrit
   ```

### Pocket ID

blaziken backs up `/var/lib/pocket-id` with a borgmatic SQLite dump of
`data/pocket-id.db` in place of the live database file.

1. Stop Pocket ID: `sudo systemctl stop pocket-id`.
2. Extract the data directory, restore the dump and give it back to
   `pocket-id`:

   ```sh
   sudo borgmatic extract --archive latest --path var/lib/pocket-id --destination /
   sudo rm -f /var/lib/pocket-id/data/pocket-id.db-wal /var/lib/pocket-id/data/pocket-id.db-shm
   sudo borgmatic restore --archive latest --database pocket-id
   sudo chown pocket-id:pocket-id /var/lib/pocket-id/data/pocket-id.db
   ```

3. Start Pocket ID: `sudo systemctl start pocket-id`.

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
