---
name: code-review
description: >
  Review a diff, branch, commit or pull request for correctness, security,
  maintainability and adherence to code-guidelines. Load when asked to review
  code or changes, check a PR, or self-review before reporting work as done.
---

# Code review

Find real problems and prove them. No style nitpicks the formatter or linter
would catch, no speculative praise.

## Scope

- Uncommitted work: `git diff` and `git diff --cached`.
- Branch: `git diff $(git merge-base HEAD main)...HEAD` and
  `git log main..HEAD`.
- Pull request: `gh pr view <n>` and `gh pr diff <n>`.

Read each changed file in full around the diff, plus callers and tests of
changed functions. A diff alone hides broken callers.

## Checklist

1. Correctness: logic errors, off-by-one, wrong conditions, unhandled empty,
   null or error cases, broken invariants, race conditions, resource leaks.
2. Callers and contracts: changed signatures, return values or behavior that
   existing callers depend on.
3. Security: secrets in the diff, injection (shell, SQL, path), unvalidated
   external input, overly broad permissions.
4. Tests: new behavior covered; tests assert behavior, not implementation;
   no disabled or weakened tests.
5. Maintainability: rules from the `code-guidelines` skill, consistency with
   surrounding code, needless abstraction or duplication.
6. Comments and docs: flag every new comment that fails the two tests in the
   global `AGENTS.md` Comments rules; docs updated where behavior changed.
7. Commits: atomic, messages match the `commit` skill.

## Verification

For each suspected problem, confirm it before reporting: trace the code path,
run the test, or construct the input that triggers it. Drop what cannot be
confirmed, or report it separately as a question.

## Output

Findings, most severe first:

```markdown
### <severity>: <one-line summary>

`path/to/file:line`

Problem: what is wrong.
Trigger: concrete input or scenario that causes it.
Fix: the change that resolves it.
```

Severities: `blocker` (bug, data loss, security), `major` (likely bug or
contract break), `minor` (maintainability), `question` (unconfirmed).

End with one line: the overall verdict. If nothing survived verification, say
so.
