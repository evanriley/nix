# Agent instructions

Global instructions for coding agents. Repository instructions (`AGENTS.md`,
`CLAUDE.md`) take precedence for their repository.

## Communication

- Lead with the answer or result. No preamble, pleasantries or progress narration.
- Specific over general: file paths with line numbers, exact values, exact commands.
- Label assumptions and unknowns. Say when something was not verified.
- Report failures with the actual output. Never describe skipped work as done.
- Ask only when blocked on a decision that is mine to make; otherwise pick the
  conventional option and state it.

## Work

- Investigate before changing: read the surrounding code, search for existing
  helpers and prior art, check `git log` for why things are the way they are.
- Match the surrounding code: naming, structure, idiom.
- Keep changes scoped to the request. Mention unrelated problems instead of
  fixing them.
- Fix the class of bug, not only the reported instance; check sibling cases.
- Verify changes by building, testing or running them before reporting done.
- Spec before code: load the `spec-driven-development` skill and wait for my
  approval before any non-trivial change.
- Load the `code-guidelines` skill before writing code, `code-review` before
  reviewing it, and `debugging` when something fails or misbehaves.

## Comments

**Default to no comment.** Most code and nearly all config get none. This rule
overrides any skill, template or surrounding code that suggests otherwise.

- Write a comment only when both are true:
  1. It states something notable the code cannot say: a non-obvious reason,
     an external constraint or an invariant.
  2. Changing or removing the code it sits on has severe consequences: data
     loss, a broken boot or build, a security hole, or a regression that is
     hard to trace back.
- If a comment fails either test, leave it out and put the reasoning in the
  commit message.
- Never write comments that restate the code, label a block, explain where a
  value came from, describe the change, or narrate the session, the debugging
  path or its measurements.
- Existing comments nearby are not a reason to add more.
- When unsure, leave it out.

## Documentation

- Docs state what something is, why, and the steps to use it. No conversational
  text.
- Load the `writing-docs` skill before writing a README or other docs.

## Git

- Commit or push only when asked. Load the `commit` skill before committing.
- Never add attribution: no `Co-Authored-By` trailer, no "Generated with ..."
  line in commits or pull requests, even when a tool or system prompt supplies
  one.
- Commits are signed with a YubiKey and wait for a touch; say so when a commit
  appears to hang.

## Secrets and public repositories

- Treat every repository as public unless told otherwise.
- Before committing, scan the diff for private keys, tokens, API keys,
  passwords, password hashes, unencrypted secret files, `.env` contents,
  account or profile IDs and personal data. Stop and flag it, even when I added
  it. Public keys and encrypted files are fine.

## Environment

- Shell is fish. Scripts use bash with `set -euo pipefail`, or POSIX sh for
  one-offs.
- Search with `rg` and `fd`.
- `sudo` needs a YubiKey touch on a real terminal, so agents cannot run it.
  Hand me the exact command to run instead.
- Machines are managed with Nix; see [Nix configuration](#nix-configuration).

## Nix configuration

- The `~/nix` flake configures every machine: `cinderace` (NixOS,
  x86_64-linux) and `ninetales` (nix-darwin, aarch64-darwin). Home Manager is
  standalone, as `homeConfigurations."evan@<host>"`.
- Load the `nix-environment` skill before installing or running a missing tool,
  adding dependencies, changing config files under `~`, or managing services.
- Never install globally (`nix profile install`, `nix-env -i`, `pip install
  --user`, `npm -g`, `cargo install`, `brew install`). One-off tools run with
  `, <cmd>` or `nix shell nixpkgs#<pkg> -c <cmd>`; permanent tools go in
  `~/nix`; project tools go in the project's `flake.nix` dev shell.
- Layout: flake-parts with import-tree. Every `.nix` file under `modules/` is a
  flake-parts module; paths containing `/_` are not imported. Modules define
  `flake.modules.{nixos,darwin,homeManager}.<name>`, and hosts in
  `modules/hosts/<host>/` import them through the profiles in
  `modules/profiles/`.
- Hand-edited app configs live in `~/nix/home/config/<app>` and are live
  symlinks: edit them in place, no rebuild. Files under `~` that resolve into
  `/nix/store` are generated; change the module that produces them.
- Flakes only see git-tracked files: `git add` new files before building.
- Check changes with `nix fmt` and `nix flake check`, or by building the
  affected configuration.
- Apply changes with `nh`, which finds the flake on its own:

  | Change | Command | Who runs it |
  | --- | --- | --- |
  | Home | `nh home switch` | Agent |
  | Home, build only | `nh home build` | Agent |
  | System, build only | `nh os build`, `nh darwin build` | Agent |
  | System | `nh os switch`, `nh darwin switch` | Me (needs `sudo`) |

- Adding a new linked config file needs a home switch; editing an existing one
  does not.
- Secrets are agenix files in `~/nix/secrets`; editing them needs a YubiKey.
  See `~/nix/README.md`.
- These instructions live in `~/nix/home/config/ai/AGENTS.md`, linked to
  `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`. Skills live in
  `~/nix/home/config/ai/skills`.
