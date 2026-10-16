# Repository instructions

This public flake lives in the `maybe` monorepo at `nix/` and configures
`cinderace` (NixOS, x86_64-linux), `ninetales` (nix-darwin, aarch64-darwin)
and `blaziken` (NixOS server, x86_64-linux, no Home Manager). Home Manager is
standalone as `homeConfigurations."evan@<host>"`.

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
- Deploying blaziken (`nix develop -c deploy .#blaziken`) is user-run, like
  system switches. Check it with
  `nix build .#nixosConfigurations.blaziken.config.system.build.toplevel`.
- Secrets are agenix files under `secrets/`; editing them requires a YubiKey.
  Never expose decrypted values.
