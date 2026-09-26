---
name: repl-driven-development
description: >
  Evaluate code in a live REPL while developing: Clojure and Babashka through
  nREPL, OCaml through the toplevel, Python through the project interpreter.
  Load when working in a Clojure, OCaml or Python project to test functions,
  inspect data, reproduce bugs or try an approach before editing files.
---

# REPL-driven development

Try code in the REPL before writing it to files. Evaluate small forms, inspect
real data, then move working code into the source and reload it.

## Loop

1. Load the namespace or module being changed.
2. Inspect the real inputs: call the function with realistic data, look at the
   shapes returned.
3. Build the change as small expressions until it produces the right results,
   including edge cases.
4. Write it into the source file, reload, and evaluate again to confirm the
   file matches what was tested.
5. Run the project's tests.

## Clojure and Babashka

`scripts/nrepl-eval` in this skill evaluates code in a running nREPL. It
finds the port from the nearest `.nrepl-port`.

```sh
<skill-dir>/scripts/nrepl-eval '(require (quote app.core) :reload) (app.core/-main)'
echo '(->> (range 10) (map inc))' | <skill-dir>/scripts/nrepl-eval --ns app.core
```

- Output prints as-is, values as `=> <value>`, exceptions as `!! <class>`
  with exit status 1.
- A REPL I started (jack-in from Kakoune) is shared: my state is visible and
  changes affect my session. Do not redefine or reset things I did not ask to
  change, and do not stop my REPL.
- No `.nrepl-port`: start one in the background from the project root with the
  dev shell loaded:
  - `deps.edn`:
    `clojure -Sdeps '{:deps {nrepl/nrepl {:mvn/version "1.7.0"} cider/cider-nrepl {:mvn/version "0.62.2"}}}' -M -m nrepl.cmdline --middleware '[cider.nrepl/cider-middleware]'`
    (add `:dev` to `-M` when `deps.edn` has a `:dev` alias)
  - `bb.edn`: `bb nrepl-server`, then write the port to `.nrepl-port`.
  Stop REPLs you started when done.
- Reload changed files with `(require '<ns> :reload)`; after renames, remove
  stale vars with `(ns-unmap '<ns> '<old-name>)`.
- Run tests in the REPL: `(clojure.test/run-tests '<test-ns>)`.

## OCaml

Pipe phrases into the toplevel; each phrase ends with `;;` and results echo as
`- : <type> = <value>`.

```sh
printf 'let x = List.init 5 Fun.id;;\nList.rev x;;\n' | ocaml -noprompt
```

With the project's libraries, build first and prepend `dune ocaml top`, which
prints the directives that load them:

```sh
dune build && { dune ocaml top; printf 'Mylib.double 21;;\n'; } | ocaml -noprompt
```

Each run starts fresh; include all setup phrases in the input. For behavior
worth keeping, write an expect test instead (`ppx_expect`, `dune test`).

## Python

Use the project's interpreter so dependencies match:

```sh
uv run python - <<'PY'
from app import main
print(main.parse("input"))
PY
```

Each run starts fresh. For repeated exploration of expensive state, write a
scratch script outside the repository and rerun it.
