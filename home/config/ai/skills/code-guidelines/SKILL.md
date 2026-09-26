---
name: code-guidelines
description: >
  Standards for writing, changing and reviewing code in any language, including
  shell and config files. Load before implementing, fixing, refactoring or
  reviewing code.
---

# Code guidelines

## Order of work

1. Understand: read the code being changed and its callers; explain why the
   current approach exists before replacing it.
2. Spec: load the `spec-driven-development` skill; present the spec and wait
   for approval unless the change is trivial.
3. Build: smallest change that implements the spec, matching surrounding code.
4. Verify: build, test or run it. Report what was run and the result.
5. Self-review the diff with the `code-review` skill before reporting done.

## Design

- Readability first. Optimize only on request or with a measured reason, and
  state the trade-off.
- Encode constraints in types: sum types or enums over boolean flags, newtypes
  for IDs, explicit nullability. Validate at external boundaries, trust
  internally.
- No casts or escape hatches (`any`, `unsafe`, `Obj.magic`, `mkForce`) without
  a reason in a short comment.
- No buried magic values. Parameterize anything that differs between hosts,
  environments or callers.
- Pass optional arguments explicitly when the default affects behavior
  (timeouts, retries, limits), so upstream default changes cannot silently
  change behavior.
- Abstract at the third occurrence, not the second. No interfaces with one
  implementation and no planned second.
- Prefer composition and plain functions over inheritance and indirection.

## Naming

- Descriptive names over comments. No abbreviations except common ones (`id`,
  `url`), and qualify those (`userId`).
- Extract a well-named function instead of commenting a block.

## Comments

- Only for what code cannot express: non-obvious why, external constraints,
  invariants, and warnings that changing the line breaks something.
- One short comment on the line it describes, or a doc comment on the
  definition. No block comments restating code.
- No comments describing the change ("now handles empty input") or the session
  that produced it.

## Errors

- Messages state what happened, what was expected, and what to do:
  `Failed to connect to localhost:5432; expected a running database. Start: docker compose up db`.
- No swallowed errors. Partial failure leaves consistent state or rolls back.

## Tests

- Test behavior through the public interface, not implementation details.
- Name tests `action_condition_expected`.
- Mock only non-determinism and I/O (time, network, filesystem).
- Cover the happy path, edge cases (empty, null, boundaries) and error paths.
- A flaky test is a bug; fix the cause, never add retries or sleeps.

## Information placement

- Code: what happens.
- Doc comment: why this shape; invariants and constraints a reader needs.
- Commit message: why this change; problem, approach, migration.
- Pull request description: how to review and verify.

## Languages

Load the reference for the language before writing it:

- Clojure: `references/clojure.md`
- OCaml: `references/ocaml.md`
- Python: `references/python.md`

Other languages: follow the community formatter and linter (`cargo fmt` and
clippy, `gleam format`, `zig fmt`), use the strongest type-system features
available, and prefer immutable data.
