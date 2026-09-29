---
name: handoff
description: >
  Continue the current work in a new Claude Code session seeded with a brief
  of this one. Load when I say "handoff" or "handoff and <goal>", or ask to
  continue in a fresh session.
---

# Handoff

Start a new background session that picks up this work without the
conversation's history.

## Steps

1. Write the brief to `~/.cache/claude-handoff/<YYYYmmdd-HHMMSS>-<slug>.md`,
   where `<slug>` is the goal in two to four kebab-case words. Write it for a
   reader with no access to this conversation, with these sections:
   - Goal: the goal I named, or the obvious next step.
   - Context: decisions made and why, and constraints I stated.
   - Files: relevant paths with line numbers, one line each.
   - State: what is done, what is verified and how, what is uncommitted.
   - Open questions.
   - First step: what the new session does first.
2. Show me the brief and wait for approval or edits.
3. From the repository root, run `claude --bg -n <slug> "$(cat <brief>)"`. It
   prints the session id.
4. Report the brief path, `claude attach <id>` to open the session now, and
   `claude --resume <session-id>` to return to it later. Read the full
   `<session-id>` from `claude agents --json` by the session's name.

## Notes

- State facts in the brief, not the path taken to reach them.
- `claude --bg` refuses directories that are not yet trusted. Report the error
  and give me the command to run from a trusted terminal.
- Do not use `/fork` or `/compact` for this: `/fork` copies the full
  conversation and `/compact` rewrites the current one.
