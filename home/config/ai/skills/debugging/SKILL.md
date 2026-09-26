---
name: debugging
description: >
  Systematic root-cause debugging. Load when something fails, crashes, hangs,
  regresses, behaves unexpectedly or differs between machines: build and eval
  errors, failing tests, broken services, errors after an update, performance
  regressions.
---

# Debugging

Find the cause before changing code. A fix without a known cause is a guess.

## Steps

1. Capture the failure exactly: full error text, command, exit code, versions,
   host. Read the whole error, including the first error in a long log, not
   only the last line.
2. Reproduce it with the smallest command possible. If it does not reproduce,
   find what differs (host, environment, inputs, state, timing) before
   anything else.
3. Form hypotheses from evidence and list them. Test the cheapest one that
   would rule out the most.
4. Narrow down:
   - `git bisect` between a known-good and bad commit; script it with
     `git bisect run <cmd>` when the check is automatable.
   - For regressions after an update, diff what changed (below).
   - Halve the input or the code path until the failure disappears.
5. Confirm the cause: explain every symptom, and predict one new observation
   that the explanation implies, then check it.
6. Fix the class of bug, not the instance. Search for the same pattern
   elsewhere (`rg`) and fix or report sibling cases.
7. Verify: the reproduction now passes, and a test or check guards it where
   the project has tests.
8. Report: symptom, cause with evidence, fix, how it was verified, and any
   sibling cases.

## Where to look

- Services on NixOS: `systemctl status <unit>`, `journalctl -u <unit> -b`,
  `journalctl --user -u <unit> -b`, `journalctl -b -p warning`.
- Services on macOS: `launchctl print gui/$(id -u)/<label>`,
  `log show --last 10m --predicate 'process == "<name>"'`.
- Nix evaluation: rerun with `--show-trace`; the relevant frame is usually the
  first one in files under `~/nix` or the project.
- Nix builds: `nix log <drv>` for the full build log; `nix build -L` to stream
  it.
- Processes: `ps -ef | rg <name>` (wrapped programs show as `.<name>-wrapped`),
  `lsof -p <pid>`, `strace -f -e trace=file <cmd>` on Linux.
- Network: `ss -tlnp`, `resolvectl query` or `dig`, `curl -v`.

## Regressions after an update

- Home or system generation: `nix store diff-closures <old> <new>`, or `nh`
  output from the switch; `home-manager generations` and
  `/nix/var/nix/profiles/system-*-link` for old generations.
- Flake inputs: `git log -p flake.lock`, then check the changelog or commits of
  the input that changed.
- To confirm, roll back the single input: `git checkout HEAD~1 -- flake.lock`
  or `nix flake lock --override-input <name> <old-ref>` and rebuild.

## Traps

- Changing several things at once hides which one mattered.
- Retries, sleeps and larger timeouts hide races; find the race.
- Errors swallowed upstream surface later as unrelated-looking failures; trace
  back to the first wrong value.
- "Works on my machine" is a difference to find, not a conclusion.
- Do not delete caches, state or lock files to make an error go away without
  knowing why they were wrong, and ask before deleting anything not
  reproducible.
