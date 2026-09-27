# OCaml

## Tooling

- dune projects; the dev shell provides `ocaml-lsp`, `utop` and
  `ocamlformat`. Format with `dune fmt` (uses `.ocamlformat`).
- Build with warnings as errors in development (dune's default dev profile);
  never silence a warning without a reason in the commit message.
- Add a dependency to `dune-project` and the library `dune` stanza, and to the
  derivation in `flake.nix`.
- Try code in the toplevel (the `repl-driven-development` skill).

## Types

- Model the domain with variants and records; make illegal states
  unrepresentable.
- Abstract types behind `.mli` interfaces for every library module; the `.mli`
  documents the contract.
- Exhaustive pattern matches; no wildcard `_` that would hide new variants.
- `option` for absence, `result` for expected failures. Exceptions only for
  programming errors or at boundaries where they are converted to `result`.
- No `Obj.magic`.

## Style

- Small modules with one responsibility; functors only when there are several
  implementations.
- Labeled arguments for parameters of the same type; optional arguments with
  explicit defaults.
- Pipelines with `|>`; `let*` / `let+` binding operators for `result` and
  `option` chains.
- Immutable data by default; `ref` and mutable fields local and justified.
- Stdlib first; add Base/Core only if the project already uses them.

## Errors

- Error types as polymorphic variants or a module-level variant with context
  fields; convert to messages at the edge.

## Testing

- Expect tests (`ppx_expect`) for behavior and output; `alcotest` for
  assertion-style tests; `qcheck` for properties.
- Tests run with `dune test`.
