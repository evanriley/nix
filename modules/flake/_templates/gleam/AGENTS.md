# app

One line saying what this project is.

## Commands

Run tools through the dev shell: `direnv allow` once, or
`nix develop -c <command>`.

- `nix build`: build the package into `result/`.
- `./ci.sh fmt`: the format check CI runs (`gleam format --check`).
- `./ci.sh test`: the checks CI runs (`gleam test`).

## Rules

- Dependencies are declared in `gleam.toml`; `gleam build` updates
  `manifest.toml`. Commit it, since the Nix build reads it.
