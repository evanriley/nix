---
name: pi-extensions
description: >
  How the pi agent harness's extensions work: where they live, how pi loads
  them, the tools, commands, guard rules and hooks each one adds, and how to
  test and type-check them. Load before changing anything under
  `~/.pi/agent/extensions` or the repo's `home/config/ai/pi/extensions`:
  tools, commands, guard rules, hooks or their tests.
---

# Pi extensions

## Layout

- Source of truth: `nix/home/config/ai/pi/extensions/`. `loop/`, `guard/`,
  `oracle/` and `vision/` are directories with an `index.ts` entry point;
  `exit.ts` is a single file. `loop/` also holds `pipeline.ts`, `worker.md` and
  `reviewer.md`, and `guard/` holds `rules.ts`.
- Home Manager symlinks each one into `~/.pi/agent/extensions/`
  (`nix/modules/programs/ai.nix:204-208`), so an edit in the repository is
  live in the next pi session without a home switch. A running session picks
  it up with `/reload`.
- Run `/reload` only while the agent is idle. It replaces the extension
  runtime, and in-memory state resets with it.

## Loading

Pi loads these TypeScript files directly through jiti: no build step, no
tsconfig, no bundling. Loading evaluates module scope only, so a reference to
a missing identifier inside a function body does not fail until that function
is called. That is how the loop shipped with its worker machinery deleted: the
`task` tool registered normally and threw `ReferenceError` on first use. Never
treat a successful load as a check; run the suites and the type check below.

## Extensions

- `loop` (`loop/index.ts`, `pipeline.ts`): the spec-driven workflow. Registers
  the `task` tool, `/approve` and `/resume-feature`, plus `session_start`,
  `turn_end` and `tool_call` hooks. A task runs from
  `~/.pi/plans/<project-slug>/<feature>/spec.md`: the worker child
  (`worker.md`) implements it, the spec's `## Checks` run, the reviewer child
  (`reviewer.md`) reviews, up to two fix passes follow, and the loop commits.
  Every task and fix pass starts a fresh worker; only a failed check resumes
  the newest worker under the 200k token cap. `/approve` covers every task
  until `spec.md` changes. `/resume-feature` continues a feature from its
  `status.md` and task records in a fresh session. `pipeline.ts` holds the pure
  helpers; only it is covered by `pipeline.test.ts`.
- `guard` (`guard/index.ts`, `rules.ts`): a `tool_call` hook that classifies
  each call for the role in `PI_LOOP_ROLE` (`main`, `worker`, `reviewer` or
  `oracle`; anything else is `main`). Secret paths always block. Risky calls
  confirm in the main session's UI, or block when there is no UI. Workers,
  reviewers and the oracle block risky and child-only calls, with a
  scratch-directory exemption for the reviewer. The hook also caps child bash
  timeouts. `rules.ts` holds the rules and `rules.test.ts` their regression
  suite.
- `oracle` (`oracle/index.ts`, `oracle.md`): registers the read-only `oracle`
  tool. It spawns one child `pi` at a time on Tencent Hy4 preview at high
  reasoning, with read, grep, find, ls, bash and web search only, and returns
  its answer with file:line references, risks and what would change its
  answer. A `thread` slug persists one conversation per project under
  `~/.pi/oracle/`. The child runs with `PI_LOOP_ROLE=oracle`, so the guard
  blocks risky calls there too.
- `vision` (`vision/index.ts`): a `context` hook for models that cannot accept
  images. It describes each image with DeepSeek V4.1 Flash (`coralbricks`
  first, `openrouter` fallback), caches descriptions under
  `$XDG_CACHE_HOME/pi/vision`, and replaces the image content with text before
  the request. Models that accept images are left alone.
- `exit.ts`: registers `/exit`, which calls `ctx.shutdown()`.

## Test

- From `nix/home/config/ai/pi/extensions`, run both suites:

  ```sh
  nix shell nixpkgs#nodejs -c node --test guard/rules.test.ts loop/pipeline.test.ts
  ```

  1978 tests today. They cover the guard classifier and the loop helpers;
  neither imports the pi runtime or `loop/index.ts`, so they cannot catch a
  missing binding in the tool or command handlers.

- `cd nix && nix flake check` runs `checks.ai-extensions`
  (`nix/modules/programs/ai.nix:273`): the same suites plus `tsc --noEmit`
  over every entry point. Stage new extension files first; the flake only sees
  tracked files and the check copies the directory from the flake source.

## Type check limits

`checks.ai-extensions` compiles against ambient stubs in
`nix/modules/programs/_ai/extensions-stubs.d.ts`. The stubs type imports from
`@earendil-works/*` and `typebox` as `any`, which catches undefined local
identifiers and syntax errors but not misuse of those packages' real APIs. A
new name imported from one of those packages fails with TS2305 until you add
it to the stub.

## Pi docs

The pi package ships its documentation under `<pi>/libexec/pi/docs/`:
`extensions.md` for the API, lifecycle, events and tool or command
registration, `skills.md` for skills, and `settings.md` for resources and
discovery. Find the installed copy with:

```sh
ls -d /nix/store/*-pi-*/libexec/pi/docs
```

For a quick experiment, load one file without touching `~/.pi`:
`pi --extension ./path/to/file.ts`.
