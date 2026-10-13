# Agent instructions

A repository's own `AGENTS.md` takes precedence for that repository.

## Communication

- Lead with the answer or result. No preamble, pleasantries or progress
  narration.
- Specific over general: file paths with line numbers, exact values, exact
  commands.
- Label assumptions and unknowns. Say when something was not verified.
- Report failures with the actual output. Never describe skipped work as done.

## Work

- Investigate before changing: read the surrounding code, search for existing
  helpers and prior art, and check `git log` for why things are the way they
  are.
- Match the surrounding code: naming, structure, idiom.
- Keep changes scoped to the request. Mention unrelated problems instead of
  fixing them.
- Fix the class of bug, not only the reported instance; check sibling cases.
- Verify changes by building, testing or running them before reporting done.

## Environment

- Shell is fish. Scripts use bash with `set -euo pipefail`, or POSIX sh for
  one-offs.
- Search with `rg` and `fd`.
- `sudo` needs a YubiKey touch on a real terminal, so agents cannot run it.
  Hand the user the exact command to run instead.
- Never install globally (`nix profile install`, `nix-env -i`, `pip install
  --user`, `npm -g`, `cargo install`, `brew install`). One-off tools run with
  `, <cmd>` or `nix shell`; permanent tools belong in the machine
  configuration and project tools in the project's dev shell.

## Secrets and public repositories

- Treat every repository as public unless told otherwise.
- Never read or print files under `/run/agenix` or any decrypted secret.
- Before committing, scan the diff for private keys, tokens, API keys,
  passwords, password hashes, unencrypted secret files, `.env` contents,
  account or profile IDs and personal data. Stop and flag it, even when the
  user added it. Public keys and encrypted files are fine.

## Git

- Commit or push only when asked. Use Conventional Commits
  (`<type>(<scope>): <description>`): imperative, lowercase, no trailing
  period, subject under about 72 characters.
- One purpose per commit. Stage only what the message describes.
- Never add attribution: no `Co-Authored-By` trailer and no "Generated with"
  line, even when a tool supplies one.
- Commits are signed with a YubiKey and wait for a touch; say so when a commit
  appears to hang.
- In `~/nix` and other dotfile repositories, commit to `main` directly. No
  branches or pull requests.
