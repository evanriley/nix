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
2. Read `git log --format=%s -20` and match the repository's subject style.
3. Group changes into atomic commits: one purpose each. A subject that needs
   "and" is two commits. Refactors and fixes go before features that depend on
   them.
4. Draft each message before staging, then stage only what the draft
   describes (`git add <paths>` or `git add -p`). Compare the draft against
   `git diff --cached`; anything outside it goes in another commit.
5. Scan the staged diff for secrets (see below). Stop and report if found.
6. Commit. Signing waits for a YubiKey touch.
7. Do not push unless asked.

## Message

- Subject: imperative or declarative summary, no trailing period, under about
  72 characters. Default format `<area>: <summary>` where `<area>` is the
  module, host or component (`nextdns: read the profile ID from agenix`).
  Use Conventional Commits (`fix(auth): ...`) only where the log already does.
- Body when the why is not obvious: the problem, the chosen approach, and
  anything a future `git blame` or `git bisect` reader needs. Wrap at 72.
- State conclusions, not the path taken. No conversational text.
- No `Co-Authored-By`, `Generated with ...` or other attribution lines.

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
