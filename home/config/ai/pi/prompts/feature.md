---
description: Spec a feature, then run its tasks through the task tool
argument-hint: "<description>"
---
Feature request: $@

Work through these steps in order. You plan and coordinate; the `task` tool runs the worker, the checks, the review and the commit for each task.

1. Research. Read the relevant code, configuration and history (`git log`). Search the web with Kagi when outside facts matter: library APIs, versions, upstream behavior.
2. Pick a short kebab-case feature slug matching `^[a-z0-9][a-z0-9-]*$`, such as `add-retry-backoff`.
3. Write the spec to `<plans>/<feature>/spec.md`, where `<plans>` is printed by:
   ```bash
   root=$(git rev-parse --show-toplevel 2>/dev/null || pwd); printf '%s/.pi/plans/--%s--\n' "$HOME" "$(printf '%s' "${root#/}" | tr '/\\:' '---')"
   ```
   Create the directory if needed. Use these sections:
   - **Goal**: the outcome in one or two sentences.
   - **Current state**: how it works today, with `file:line` references and real values.
   - **Desired state**: before and after for each behavior that changes.
   - **Tasks**: `## Tasks` with one heading per task, `### Task <n>: <conventional commit subject>`, n counting from 1. Under each heading list the files the task owns and what to do. Each task is one commit that builds and passes CI on its own. At most 8 tasks; if the work needs more, propose splitting it into several features and STOP.
   - **Checks**: `## Checks` whose first fenced code block holds shell commands, one per line; blank lines and `#` lines are skipped. They run from the repository root after every task, so prefix each with `cd <dir> &&` when it must run elsewhere. Use the repository's AGENTS.md verification commands (in this monorepo: `cd nix && nix fmt` and `cd nix && nix flake check` for nix, the project's `ci.sh` otherwise). Commands must be non-interactive and exit non-zero on failure.
   - **Acceptance**: what the user will look at: a demo command and what to see; for UI work, the screens to capture with the project's headless GUI script and the reference images to compare against; a run on real data where it applies.
   - **Edge cases**: concrete input and the expected result for each.
   - **Alternatives**: approaches rejected and why.
   - **Risks and rollback**: what can break and how to undo it.
   - **Open questions**: decisions the user must make; write "None" when there are none.
4. Print the entire spec.md in chat, every section, then STOP. Tell the user to approve it with `/approve` or to request changes.
5. When you receive "Approved: run the tasks for <feature>", call `task` for each task in order, one at a time, with the feature slug, the task number and a standalone brief (each task starts a fresh worker with no prior context): what matters from research, pitfalls, and the user's notes. Do not stop between tasks to ask the user. Stop early only on a `blocked` result or an open question the spec cannot answer; then report the stage, the reason and the file paths and STOP. Do not fix anything yourself. If `task` says spec.md changed, ask the user to run `/approve` again.
6. Rules. Never edit or write files in the repository; write only `spec.md` and `status.md` in the plans directory. Never commit, amend, rebase or split commits, and never do the worker's job yourself. Read-only commands, the Checks, the demo command and the headless GUI script are fine. Run GUI and audio only through the project's headless scripts and silent sink, never on the user's desktop or speakers.
7. When all tasks are committed, run the Acceptance yourself: the demo command, and screenshots with the headless script, reading each image and comparing it with its reference. Then report:
   - `git log --oneline <base>..HEAD`, where `<base>` is the upstream default branch;
   - the screenshot paths next to their references, with what differs;
   - the demo command;
   - the non-blocking findings from the task results;
   - the total cost, summed from `<plans>/<feature>/task-*.json`.

   Then STOP. The user ships with `/ship` or asks for changes; changes become a new task appended to `spec.md`, which needs a new `/approve`.
8. When told the context cap was reached, write `<plans>/<feature>/status.md` and stop: tasks committed with their shas, the current task and its state, what is next, open decisions, and anything the user said that the spec does not record. The user continues with `/resume-feature <feature>`.
