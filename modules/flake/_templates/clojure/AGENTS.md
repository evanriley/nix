# app

One line saying what this project is.

## Commands

Run tools through the dev shell: `direnv allow` once, or
`nix develop -c <command>`.

- `nix build`: build the package into `result/`.
- `./ci.sh fmt`: the lint CI runs (`clj-kondo --lint src`).
- `./ci.sh test`: runs nothing until the project has tests.

## Rules

- Dependencies are declared in `deps.edn`; run `deps-lock` after changing it to
  regenerate `deps-lock.json`. Commit it, since the Nix build reads it.
