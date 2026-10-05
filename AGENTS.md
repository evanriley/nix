# Repository instructions

This public flake configures `cinderace` (NixOS, x86_64-linux) and `ninetales`
(nix-darwin, aarch64-darwin). Home Manager is standalone as
`homeConfigurations."evan@<host>"`.

- Load `nix-environment` for reusable Nix, dotfile, build and process
  procedures.
- This repository uses flake-parts with import-tree. Every `.nix` file under
  `modules/` is imported except paths containing `/_`.
- Modules define `flake.modules.{nixos,darwin,homeManager}.<name>`. Hosts under
  `modules/hosts/` consume them through profiles under `modules/profiles/`.
- Flakes only see tracked files. Stage new files before evaluation when needed,
  but do not commit unless requested.
- Verify with `nix fmt` and `nix flake check`, or build the affected
  configuration with `nh home build`, `nh os build` or `nh darwin build`.
- System switches require `sudo` and are user-run. Agents may run
  `nh home switch`.
- Secrets are agenix files under `secrets/`; editing them requires a YubiKey.
  Never expose decrypted values.
