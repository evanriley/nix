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

## Delegation

I ask you to delegate. In the main session you plan and orchestrate; the agents
in `~/.claude/agents` do the work.

- Keep for yourself: talking with me, specs and approval, choosing agents,
  reviewing their output, final verification and commits.
- Work inline, without spawning, for edits of a few lines to files already in
  context and for single-command checks.
- Use direct tools for exact path, symbol or string lookups. Use `search` for
  multi-step behavioral discovery or findings that must correlate across the
  codebase. Research external code and docs with `librarian`. Recover earlier
  sessions with `read-thread`.
- The main planner owns routing. Use `worker` (Sonnet, medium) when the
  implementation route is established. Use `worker-deep` (Opus, medium) when
  requirements are settled but the implementation route must be determined.
- Use `worker-high` (Opus, xhigh) only for critical, weakly-verifiable
  invariants or high-consequence paths such as concurrency, data loss,
  security or boot. Task size alone does not qualify.
- When I name a worker role or `oracle`, use it and skip its criteria.
- Size each worker task to one commit. A worker running past about 40 minutes
  means the task was too big; split the next one.
- When a hand-back has an execution mistake, return the findings to the same
  agent once. When its route was wrong, use `worker-deep`. When the cause is
  unknown, use `worker-deep` with the `debugging` skill to reproduce and narrow
  it; keep the diagnosis for yourself.
- Run workers in parallel only for parts with disjoint files, at most three at
  once. Never run oracles in parallel.
- Use `oracle` before the spec for `worker-high`-grade work, after proposing it
  in one line and getting my yes; when the cause is still unknown after a
  debugging worker narrowed it; or when I ask. Never consult oracle solely to
  choose a worker. If already consulted, oracle should recommend the worker.
  Use one oracle per feature and resume it for follow-ups.
- Give each worker a self-contained handoff containing the outcome, settled
  requirements, governing pattern and ownership, residual decisions,
  constraints and non-goals, acceptance checks, and critical invariants.
- Review worker output from its diff and evidence block: each acceptance
  criterion has a command and output behind it, the files match the spec, no
  test was weakened. Run runnable criteria yourself instead of reasoning about
  them.
- While a worker runs, write the next spec or review the previous diff.
- In Codex, spawn these agents by name through `agent_type`; `explorer` is not
  `search`, and `read-thread` is Claude Code only.
- Say which agent you chose and why in one line.

## Compact Instructions

Keep the approved spec verbatim, decisions and their reasons, which agents are
running or were resumed, verification state, and uncommitted files. Drop file
contents and command output that were already acted on.

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
- Load the `nix-environment` skill before installing or running a missing tool,
  adding dependencies, changing config files under `~`, or managing services.
- Never install globally (`nix profile install`, `nix-env -i`, `pip install
  --user`, `npm -g`, `cargo install`, `brew install`). One-off tools run with
  `, <cmd>` or `nix shell`; permanent tools belong in the machine
  configuration and project tools in the project's dev shell.
