---
name: commit
description: >
  Create git commits: splitting changes into atomic commits, writing messages,
  and checking diffs for secrets before committing. Load whenever asked to
  commit, amend, split commits, write a commit message or open a pull request.
---

# Commit

## Steps

1. Read `git status`, `git diff` and `git diff --cached`.
2. Check the repository for its own commit conventions (`AGENTS.md`,
   `CLAUDE.md`, `CONTRIBUTING.md`, commitlint config). Use Conventional
   Commits unless the repository or I state otherwise. Read
   `git log --format=%s -20` for the scopes in use.
3. Group changes into atomic commits: one purpose each. A subject that needs
   "and" is two commits. Refactors and fixes go before features that depend on
   them. In a series of commits, such as a pull request, only the final commit
   has to build and pass tests; do not build or test each intermediate commit.
4. Draft each message before staging, then stage only what the draft
   describes (`git add <paths>` or `git add -p`). Compare the draft against
   `git diff --cached`; anything outside it goes in another commit.
5. Scan the staged diff for secrets (see below). Stop and report if found.
6. Commit. Signing waits for a YubiKey touch.
7. Do not push unless asked.

## Message

Use [Conventional Commits](https://www.conventionalcommits.org/) unless told
otherwise, following
[qoomon's cheatsheet](https://gist.github.com/qoomon/5dfcdf8eec66a051ecd85625518cfd13):

```text
<type>(<optional scope>): <description>

<optional body>

<optional footer>
```

- Initial commit: `chore: init`.
- Merge commit: git's default, `Merge branch '<branch name>'`.
- Revert commit: git's default, `Revert "<reverted commit subject line>"`.
- Wrap the body and footer at 72 columns. State conclusions, not the path
  taken. No conversational text.
- No `Co-Authored-By`, `Generated with ...` or other attribution lines.

### Types

- `feat`: add, adjust or remove a feature of the API or UI.
- `fix`: fix an API or UI bug from a prior `feat` commit.
- `refactor`: rewrite or restructure code without changing API or UI
  behavior.
- `perf`: a `refactor` that improves performance.
- `style`: whitespace, formatting, semicolons; no change in behavior.
- `test`: add missing tests or correct existing ones.
- `docs`: changes that only affect documentation.
- `build`: build tools, dependencies, project version.
- `ops`: infrastructure, deployment scripts, CI/CD, backups, monitoring.
- `chore`: anything else, such as the initial commit or `.gitignore`.

### Scope

- Optional. Gives context: the module, host or component
  (`fix(nextdns): read the profile ID from agenix`).
- Use the scopes the repository already uses.
- Never use issue identifiers as scopes.

### Breaking changes

- Mark a breaking change with `!` before the `:`:
  `feat(api)!: remove status endpoint`.
- Describe it in the footer when the description does not make it clear.

### Description

- Mandatory. A concise summary of the change.
- Imperative, present tense: "change", not "changed" or "changes".
- Lowercase first letter. No trailing period.
- Keep the subject line under about 72 characters.

### Body

- Optional; write one when the why is not obvious.
- The motivation for the change and how it contrasts with the previous
  behavior, plus anything a future `git blame` or `git bisect` reader needs.
- Imperative, present tense.

### Footer

- Optional, except for breaking changes.
- Issue references: `Closes #123`, `Fixes JIRA-456`.
- Breaking changes start with `BREAKING CHANGE:`, followed by a space for a
  single line or by two newlines for several lines.

### Examples

```text
feat: add email notifications on new direct messages
```

```text
feat!: remove ticket list endpoint

refers to JIRA-1337

BREAKING CHANGE: ticket endpoints no longer supports list all entities.
```

```text
fix(api): fix wrong calculation of request body checksum
```

```text
fix: add missing parameter to service call

The error occurred due to <reasons>.
```

```text
perf: decrease memory footprint for determine unique visitors by using HyperLogLog
```

```text
build(release): bump version to 1.0.0
```

```text
style: remove empty line
```

## Secret scan

Block the commit when the diff contains:

- private keys, tokens, API keys, passwords or password hashes
- unencrypted secret files, `.env` contents, key exports
- account or profile IDs that grant access (for example a NextDNS profile ID)
- personal data (addresses, phone numbers, documents)

Allowed: public keys, age recipients, SSH host public keys, encrypted `.age`
files.

## Pull requests

- Title follows the subject style.
- Body: what changed, why, how it was verified, and what to look at closely.
- No attribution lines.
