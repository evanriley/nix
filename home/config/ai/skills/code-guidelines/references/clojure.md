# Clojure

## Tooling

- `deps.edn` projects; the dev shell provides `clojure`, `clojure-lsp`,
  `clj-kondo` and `babashka`. Nix builds use clj-nix: after changing
  `deps.edn`, regenerate `deps-lock.json` with `deps-lock`.
- Lint with `clj-kondo --lint src test`; clean before reporting done.
- Develop against a running REPL (the `repl-driven-development` skill).
- Scripts and tooling tasks in Babashka (`bb.edn` tasks) rather than shell.

## Data and design

- Plain data first: maps, vectors, sets and keywords. Functions transform data;
  side effects live at the edges.
- Namespaced keywords for domain data (`:user/id`).
- Pure functions by default. Side-effecting functions end in `!`.
- Describe data shapes at boundaries with malli or `clojure.spec`, and validate
  external input there.
- Records and protocols only for polymorphism with a real second
  implementation; multimethods for open dispatch on data.
- State in a small number of atoms owned by one namespace; no global mutable
  state scattered across namespaces.

## Style

- Threading macros (`->`, `->>`, `some->`, `cond->`) for pipelines; `let` to
  name intermediate values that need names.
- Destructure in arguments and `let`.
- `when` over single-branch `if`; `cond` over nested `if`.
- `:require` with `:as` aliases; no `:refer :all` or `:use`.
- Docstrings on public functions that state what the function returns and any
  non-obvious contract; no docstrings restating the name.

## Errors

- `ex-info` with a message and a data map describing the context; catch at the
  edges with `ex-data`.
- Return `nil` only when absence is expected and documented.

## Testing

- `clojure.test` with `deftest`, `testing` blocks for scenarios, `are` for
  input tables.
- Property tests with `test.check` for pure data transformations.
