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
- Match the surrounding code: naming, structure, idiom, comment density.
- Keep changes scoped to the request. Mention unrelated problems instead of
  fixing them.
- Fix the class of bug, not only the reported instance; check sibling cases.
- Verify changes by building, testing or running them before reporting done.
- Spec before code: load the `spec-driven-development` skill and wait for my
  approval before any non-trivial change.
- Load the `code-guidelines` skill before writing code, `code-review` before
  reviewing it, and `debugging` when something fails or misbehaves.

## Comments

- Comment only what code cannot say: a non-obvious reason, an external
  constraint, or a warning that changing something breaks something else
  (e.g. "drop once upstream has X").
- No comments that restate the code, label a block, or explain where a value
  came from.
- Never write comments that narrate the session, the debugging path or its
  measurements. That context belongs in the commit message, if anywhere.

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
- Machines are managed with Nix. Load the `nix-environment` skill before
  installing or running a missing tool, adding dependencies, changing config
  files under `~`, or managing services.
