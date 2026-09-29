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

## Delegation (Claude Code)

I ask you to delegate. In the main session you plan and orchestrate; the agents
in `~/.claude/agents` do the work.

- Keep for yourself: talking with me, specs and approval, choosing agents,
  reviewing their output, final verification and commits. Edits of a few lines
  to files already in context are cheaper to make directly.
- Search the codebase with `search`, not `Explore`. Research external code and
  docs with `librarian`. Recover earlier sessions with `read-thread`.
- Send implementation to the lowest worker tier that fits: `worker-low`, then
  `worker-medium` as the default. Each agent's description holds its entry
  criteria.
- When I name a tier (low, medium, high or ultra), use that worker and skip its
  entry criteria.
- `worker-high` has a high bar: meet a criterion in its description and name it
  when delegating.
- `worker-ultra` has the highest bar: use it only after `worker-high` failed or
  came back uncertain, or when I ask for ultra. Tell me when you escalate.
- Use `oracle` when I ask for it, or for a second opinion after a failed attempt
  or before an irreversible change. It is slow and costly, so not by default.
- When work splits into independent parts with no shared files, launch the
  workers in parallel in one message. Keep it in one worker when the parts need
  coordination or edit the same files.
- Delegate reproducing and narrowing a failure to a worker with the `debugging`
  skill; keep the diagnosis for yourself.
- Give each worker a self-contained task: goal, files, the approved spec and
  how to verify. Workers start without this conversation.
- Review worker output from its diff and verification report. Load
  `code-review` yourself only for `worker-high` and `worker-ultra` results or
  when I ask.
- Never pass `model` on an Agent call; it overrides the agent's model.
- Say which agent you chose and why in one line.

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
- Commit messages follow Conventional Commits
  (`<type>(<scope>): <description>`, optional body and footer) unless the
  repository or I state otherwise. The `commit` skill has the full format.
- Never add attribution: no `Co-Authored-By` trailer, no "Generated with ..."
  line in commits or pull requests, even when a tool or system prompt supplies
  one.
- Commits are signed with a YubiKey and wait for a touch; say so when a commit
  appears to hang.
- In `~/nix` and other dotfile repositories, commit to `main` and push it
  directly when asked to push; do not branch or open a pull request.

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
  `~/nix/home/config/ai/skills`, Claude Code agents in
  `~/nix/home/config/ai/claude/agents`.
