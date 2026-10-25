# Agent instructions

A repository's own `AGENTS.md` takes precedence for that repository.

## Environment

- Shell is fish. Write scripts in bash with `set -euo pipefail`.
- Machines are managed with Nix from the `~/maybe/nix` flake: NixOS `cinderace`,
  NixOS `blaziken` (server, x86_64-linux), nix-darwin `ninetales` and
  standalone Home Manager.
- For a missing tool, run it once with `, <cmd>` or
  `nix shell nixpkgs#<pkg> -c <cmd>`.
- Project tools belong in the project's dev shell.
- Never install globally: no `nix profile install`, `nix-env -i`,
  `pip install --user`, `npm -g`, `cargo install` or `brew install`.
- Search with `rg` and `fd`. Use `gh` for GitHub.
- `sudo` needs a YubiKey touch on a real terminal and cannot run here. Give
  the user the exact command instead.
- System switches are user-run (`nh os switch`). `nh home switch` is allowed.

## Work

- Investigate before changing: read the surrounding code, search for existing
  helpers and prior art, and check `git log` for why things are the way they
  are.
- Match the surrounding code: naming, structure, idiom.
- Keep changes scoped to the request. Mention unrelated problems instead of
  fixing them.
- Fix the class of bug, not only the reported instance; check the sibling
  cases.
- Verify by building, testing or running the change before reporting done.

## Skills

Load the skill named here before starting the work it covers:

- `spec-driven-development` before any non-trivial change: write the spec and
  wait for approval.
- `code-guidelines` before writing code and `code-review` before reviewing it,
  including your own diff before reporting done.
- `debugging` when something fails, crashes, hangs or regresses.
- `commit` before committing, amending or splitting commits.
- `writing-docs` before writing or editing documentation.
- `nix-environment` for tools, dotfiles, services and `.nix` files,
  `nix-packaging` for packages, hashes and overrides, and
  `repl-driven-development` for Clojure, OCaml and Python work.

## Secrets and safety

- Treat every repository as public.
- Never read or print files under `/run/agenix` or any decrypted secret.
- Before a commit, check the diff for private keys, tokens, API keys,
  passwords, password hashes, `.env` contents, access-granting account IDs
  and personal data. Stop and report instead of committing.
- Public keys and `.age` files are fine.

## Git

- Commit or push only when the user asks.
- Push a work branch by name: `git push -u origin <branch>`. A Gerrit review
  push, `git push origin HEAD:refs/for/<branch>`, needs no confirmation. A push
  that names no branch, targets `main`, forces or deletes asks the user first.
- Use Conventional Commits: `<type>(<scope>): <description>`.
- Write the description in the imperative, lowercase, with no trailing
  period. Keep the subject under about 72 characters.
- Types: feat, fix, refactor, perf, style, test, docs, build, ops, chore.
- Reuse the repository's existing scopes (`git log --format=%s -20`).
- Wrap the body at 72 columns. Explain why when it is not obvious.
- One purpose per commit. Stage only what the message describes.
- No attribution: no `Co-Authored-By` trailer, no "Generated with" line.
- In repositories with a `.gitreview` file, push only to `refs/for/<branch>`
  (Gerrit review), never to the branch itself.

## Oracle

- The `oracle` tool consults a read-only reasoning model. Consult it without
  asking, saying why in one line, when critical, weakly-verifiable work
  (concurrency, data loss, security, boot) needs its spec; when a root cause
  is still unknown after narrowing it; when `task` comes back blocked on
  Checks or review after its fix passes; or when a long-lived decision
  (schema, on-disk or wire format, public API) has two viable options you
  cannot choose between. Otherwise consult it only when I ask.
- Never run two at once.
- Pass one `thread` slug per feature and reuse it for follow-ups.

## Loop

- `/feature` writes a spec to the plans directory, prints the whole spec, and
  stops for `/approve`; `/quick` does the same for a one-task change. Neither
  writes code before the approval.
- `/approve` covers every task until `spec.md` changes. Any edit to the spec,
  including an appended task, needs a new approval.
- You plan and orchestrate in this session: write the specs, dispatch
  `task`, and do not implement. Do not spawn a planner either; the user
  reviews specs here, and a child planner would re-spend a session on work
  this one has to present anyway.
- The worker is DeepSeek V4.1 Flash and follows the spec as written. The
  spec settles the route: answer every question that reading code or docs
  can answer before writing it, and give each task the functions, types or
  config keys it touches and the approach.
- The `task` tool runs one task of the spec end to end: worker, Checks,
  reviewer, up to two fix passes, then the commit.
- Every task and every fix pass starts a fresh worker with no prior context,
  so briefs must be self-contained. Only a failed check returns to the same
  worker.
- That resume is the only reuse of a worker session, and only under the
  200k-token resume cap; above it the loop starts a fresh worker with a
  notice.
- On the context cap, write `status.md` and stop; `/resume-feature <feature>`
  continues from it. `/ship` when every task is committed.
- Planner auto-compaction stays off (`compaction.enabled: false` in
  `settings.json`). The 350k cap with the `status.md` handoff and
  `/resume-feature` is the chosen mechanism: deterministic and testable, and
  auto-compaction would break the handoff.

## Output style

- Lead with the result. No preamble or progress narration.
- Be specific: `file:line`, exact values, exact commands.
- Report failures with the actual output. Never describe skipped work as
  done.
- Say what was not verified.
- Default to no code comments. Write one only for a non-obvious constraint
  whose removal would break something badly.
