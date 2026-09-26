---
name: spec-driven-development
description: >
  Write a spec and wait for approval before implementing. Load before any code
  change that is not trivial: new features, behavior changes, refactors,
  multi-file changes, new modules or packages, and bug fixes whose cause or fix
  is not obvious.
---

# Spec-driven development

No implementation until I approve the spec.

## When a spec is required

Required for everything except:

- typos, formatting, renames within one file
- one-line fixes where the cause and fix are both obvious
- changes where I specified exactly what to change
- throwaway exploration that will not be kept

When unsure, write the spec; a short one is cheap.

## Steps

1. Research. Read the affected code, its callers and tests, `git log` for the
   area, and upstream docs for any library or tool involved. Resolve the full
   shape of every type or config being changed. Record open questions instead
   of guessing.
2. Write the spec from `assets/spec-template.md`. Omit sections that do not
   apply. Scale it to the change: a small fix gets a few lines per section.
3. Present the spec and stop. Wait for approval or changes.
4. On approval, implement exactly the spec. If implementation reveals the spec
   is wrong, stop and present the revision instead of improvising.
5. Verify against the acceptance criteria and report each one as met or not.

## Where the spec lives

In the conversation. Write it to a file only when I ask, outside the
repository unless I name a path.

## Quality bar

- Current state cites code: `file:line`, real config values, example data.
- Desired state shows before and after for each behavior change.
- Edge cases are concrete inputs with expected results, not categories.
- Acceptance criteria are checks someone else could run.
- Alternatives name what was rejected and why.
