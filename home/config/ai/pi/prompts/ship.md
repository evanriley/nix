---
description: Commit the finished work, send it for review or open a pull request, wait for CI and merge a pull request
argument-hint: "[notes]"
---
Ship the work in this repository. Notes from the user: ${@:-none}

Work through these steps in order and stop at the first one that fails. Run every command yourself; do not dispatch the worker. Running this command is the user's approval to commit and push, and, for a GitHub pull request, to merge.

If the repository root has a `.gitreview` file, follow the Gerrit steps. Otherwise follow the GitHub steps.

## Gerrit

Read `host`, `port`, `project` and `defaultbranch` (default `main`) from `.gitreview`, and the SSH user from the `origin` URL. `gerrit` below means `ssh -p <port> <user>@<host> gerrit`.

1. Check there is something to ship. Run `git fetch origin`. If `git status --short` is empty and `git log origin/<branch>..HEAD` is empty, say so and stop. If this work came from `/feature` and its latest review verdict is not "pass", say so and stop unless the notes say to ship anyway.
2. Scan for secrets. Read `git diff HEAD` and every untracked file that git does not ignore for private keys, tokens, API keys, passwords, password hashes, `.env` contents, account IDs and personal data. On a hit, stop and report the file and line without printing the value.
3. Check the `commit-msg` hook exists at `$(git rev-parse --git-path hooks/commit-msg)`. If it is missing, stop and give the user the `scp` command for it from the repository README.
4. Commit on the current branch; do not create a branch. Group the changes into atomic Conventional Commits, staging by path only what each message describes. Each commit becomes its own change with its own CI build, so each must build on its own. Never edit or remove a `Change-Id` trailer.
5. Rebase with `git rebase origin/<branch>`. On a conflict, run `git rebase --abort`, report the conflicting files and stop.
6. Push with `git push origin HEAD:refs/for/<branch>`. Record each change number and URL from the output.
7. Wait for CI. For each change, poll `gerrit query --format=JSON --current-patch-set change:<number>` every 30 seconds, for up to 3600 seconds, until `.currentPatchSet.approvals` has a `Verified` vote by the `buildkite` user on the patchset you pushed. On a timeout, report the changes still without a vote and stop.
8. If a change has Verified -1, show the `buildkite` message for it from `gerrit query --comments change:<number>` (it links the build), say whether the failure comes from the change or from the CI infrastructure, and stop. Do not rerun or fix anything until the user says to.
9. Report each change URL with its Verified vote. Do not vote Code-Review and do not submit; the user reviews and submits.

## GitHub

1. Check there is something to ship. Find the default branch with `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`. If `git status --short` is empty and the current branch has no commits the default branch lacks, say so and stop. If this work came from `/feature` and its latest review verdict is not "pass", say so and stop unless the notes say to ship anyway.
2. Scan for secrets. Read `git diff HEAD` and every untracked file that git does not ignore for private keys, tokens, API keys, passwords, password hashes, `.env` contents, account IDs and personal data. On a hit, stop and report the file and line without printing the value.
3. Branch. If you are on the default branch, create `<type>/<slug>`, where `<type>` is the Conventional Commits type of the change and `<slug>` is the feature slug.
4. Commit. Tell the user that pushes wait for a YubiKey touch. Group the changes into atomic Conventional Commits, staging by path only what each message describes.
5. Push with `git push -u origin <branch>`. Always name the branch.
6. Open the pull request. Reuse the one `gh pr view` reports for this branch; otherwise run `gh pr create` with a title in the commit subject style and a body covering what changed, why, how it was verified and what to look at closely. No attribution lines.
7. Wait for CI. Record the pushed commit with `git rev-parse HEAD`, then run `gh pr checks --watch --fail-fast --interval 20` with a timeout of 3600 seconds. If it reports no checks, wait 20 seconds and try again, for up to 2 minutes; if there are still none, stop and do not merge.
8. If a check fails, do not merge. Find the run with `gh run list --branch <branch> --limit 1 --json databaseId,conclusion`, print the tail of `gh run view <id> --log-failed`, name the failing jobs, say whether the failure comes from the change or from the CI infrastructure, and stop. Do not rerun or fix anything until the user says to.
9. Merge. Pick the first method the repository allows, in the order rebase, squash, merge, from `gh api repos/{owner}/{repo} --jq '{allow_rebase_merge, allow_squash_merge, allow_merge_commit}'`. Run `gh pr merge --<method> --delete-branch --match-head-commit <recorded commit>`. Never pass `--admin` or `--auto`.
10. Confirm. `git status -sb` and `git log --oneline -3` must show the default branch at the merged commit with a clean tree. If the checkout is still on the work branch, switch to the default branch, run `git pull --ff-only` and delete the work branch. Report the pull request number and URL and the merged commit.
