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

## Research

- Web search and page extraction: the `kagi` MCP tools.
- Library and API documentation for a specific version: the `context7` MCP
  tools.
- Literal code search across public GitHub repositories: the `grep_app` MCP
  tools.
- Never put this repository's code, paths or data in a query to these
  services.

## Worktrees

- In `~/maybe`, create worktrees with `nix run ./nix#worktree -- <name>`. The
  `worktree` tool leaves a checkout without the pre-commit configuration.

## Output style

- Lead with the result. No preamble or progress narration.
- Be specific: `file:line`, exact values, exact commands.
- Report failures with the actual output. Never describe skipped work as
  done.
- Say what was not verified.
- Default to no code comments. Write one only for a non-obvious constraint
  whose removal would break something badly.
