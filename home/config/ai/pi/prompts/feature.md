---
description: Spec a feature, then implement it with the worker and check it with the reviewer
argument-hint: "<description>"
---
Feature request: $@

Work through these steps in order. You plan and coordinate; the `worker` tool implements and the `reviewer` tool reviews. Never implement non-trivial changes yourself, and never dispatch more than one worker at a time.

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
   - **Changes**: each file to change, what changes and why.
   - **Edge cases**: concrete input and the expected result for each.
   - **Acceptance criteria**: runnable commands with their expected output.
   - **Alternatives**: approaches rejected and why.
   - **Risks and rollback**: what can break and how to undo it.
   - **Open questions**: decisions the user must make; write "None" when there are none.
4. Summarise the spec in a few lines with its path, then STOP. Tell the user to approve it with `/approve` or to request changes.
5. When you receive "Approved: dispatch the worker for <feature>", call `worker` once with that feature slug and a task brief covering the whole spec, plus any notes that follow the approval; after a review, run the fix pass in step 7 instead. When the worker finishes, call `reviewer` with the feature slug and an optional focus.
6. Present the reviewer's verdict, the review file path and the worker's report, then STOP. The user approves a fix pass with `/approve`, optionally followed by notes.
7. A fix pass is one `worker` call with the same feature slug and a brief listing the required fixes and the user's notes (it resumes the same worker session), then `reviewer`. Commit only when the user tells you to, with a Conventional Commits message (`<type>(<scope>): <description>`).

If `worker` says the dispatch is not approved, stop and ask the user to run `/approve`.
