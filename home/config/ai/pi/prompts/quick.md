---
description: Spec and run a small one-commit change
argument-hint: "<description>"
---
Change request: $@

Work through these steps in order. You plan and coordinate; the `task` tool runs the worker, the checks, the review and the commit.

1. Research briefly. Read the relevant code and history (`git log`). Search the web with Kagi only when outside facts matter. Answer every question that reading code or docs can answer before writing the spec. An unchecked question, an unfamiliar API, a large file or crossing repositories is research to do now, not something to leave to the worker.
2. Pick a short kebab-case feature slug matching `^[a-z0-9][a-z0-9-]*$`.
3. Write a short spec to `<plans>/<feature>/spec.md`, where `<plans>` is printed by:
   ```bash
   root=$(git rev-parse --show-toplevel 2>/dev/null || pwd); printf '%s/.pi/plans/--%s--\n' "$HOME" "$(printf '%s' "${root#/}" | tr '/\\:' '---')"
   ```
   Create the directory if needed. Use these sections:
   - **Goal**: the outcome in one or two sentences.
   - **Tasks**: `## Tasks` with exactly one heading, `### Task 1: <conventional commit subject>`, followed by the files it owns, the functions, types or config keys it touches, and the approach; for external APIs, the calls used, with a doc or source reference. The worker follows it without choosing an approach.
   - **Checks**: `## Checks` whose first fenced code block holds shell commands, one per line; blank lines and `#` lines are skipped. They run from the repository root, so prefix each with `cd <dir> &&` when it must run elsewhere. Use the repository's AGENTS.md verification commands. Commands must be non-interactive and exit non-zero on failure.
   - **Acceptance**: a demo command or how to see the change.
4. Show the whole spec in chat, then STOP. Tell the user to approve it with `/approve` or to request changes.
5. When you receive "Approved: run the tasks for <feature>", call `task` with the feature slug, task number 1 and a standalone brief (each task starts a fresh worker with no prior context): what matters from research, pitfalls, and the user's notes. Stop on a `blocked` result and report the stage, the reason and the file paths. Do not fix anything yourself. If `task` says spec.md changed, ask the user to run `/approve` again.
6. Rules. Never edit or write files in the repository; write only `spec.md` and `status.md` in the plans directory. Never commit, amend, rebase or split commits, and never do the worker's job yourself. Read-only commands, the Checks, the demo command and the headless GUI script are fine. Run GUI and audio only through the project's headless scripts and silent sink, never on the user's desktop or speakers.
7. When the task is committed, run the Acceptance yourself, then report `git log --oneline <base>..HEAD` (`<base>` is the upstream default branch), the demo command and what you saw, the non-blocking findings from the task result, and the cost from `<plans>/<feature>/task-1.json`. Then STOP. The user ships with `/ship` or asks for changes; changes become a new task appended to `spec.md`, which needs a new `/approve`.
8. When told the context cap was reached, write `<plans>/<feature>/status.md` (tasks committed with shas, the current task and its state, what is next, open decisions, anything the user said that the spec does not record) and stop. The user continues with `/resume-feature <feature>`.
