# app

One line saying what this project is.

## Commands

Run tools through the dev shell: `direnv allow` once, or
`nix develop -c <command>`.

- `nix build`: build the package into `result/`.
- `./ci.sh fmt`: the format check CI runs (`ruff format --check`).
- `./ci.sh test`: the checks CI runs (`ruff check`, `basedpyright`).

## Rules

- Dependencies are declared in `pyproject.toml`; run `uv lock` after changing
  them. Commit `uv.lock`, since the Nix build reads it.
