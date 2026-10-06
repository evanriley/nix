# Agent instructions

Repository instructions (`AGENTS.md`, `CLAUDE.md`) take precedence for their
repository.

## Communication

- Lead with the answer or result. No preamble or progress narration.
- Be specific: file paths with line numbers, exact values, exact commands.
- Say what was not verified. Report failures with the actual output.
- Ask only when blocked on a decision that is mine to make.

## Work

- Read the surrounding code before changing it, and match its style.
- Keep changes scoped to the request; mention unrelated problems instead of
  fixing them.
- Verify by building, testing or running before reporting done.
- For a non-trivial change, propose a short plan and wait for my approval.
- Default to no code comments. Write one only for a non-obvious constraint whose
  removal would break something badly.

## Subagents

- Use subagents only when I ask, including through `/implement` (scout →
  planner → worker → reviewer) or `/scout-and-plan` (stops after the plan).
- A subagent never calls the `subagent` tool.

## Git

- Commit or push only when asked. Load the `commit` skill before committing.
- No attribution lines or `Co-Authored-By` trailers.
- Commits are signed with a YubiKey and wait for a touch.
- In `~/nix` and other dotfile repositories, commit to `main` directly.

## Secrets

- Treat every repository as public. Before committing, check the diff for keys,
  tokens, passwords and personal data; stop and tell me if any are present.
- Never read or print files under `/run/agenix`.

## Environment

- Shell is fish. Scripts use bash with `set -euo pipefail`.
- Search with `rg` and `fd`. Use `gh` for GitHub.
- `sudo` needs a YubiKey touch; give me the exact command instead.
- Load the `nix-environment` skill before installing or running a missing tool,
  adding dependencies, or changing config under `~`.
- Never install globally. One-off tools run with `, <cmd>` or `nix shell`.
