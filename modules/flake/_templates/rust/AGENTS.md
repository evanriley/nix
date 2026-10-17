# app

One line saying what this project is.

## Commands

Run tools through the dev shell: `direnv allow` once, or
`nix develop -c <command>`.

- `nix build`: build the package into `result/`.
- `./ci.sh fmt`: the format check CI runs (`cargo fmt --check`).
- `./ci.sh test`: the checks CI runs (`cargo clippy -- -D warnings`,
  `cargo test`).

## Rules

- Dependencies come from crates.io through `Cargo.toml`; commit `Cargo.lock`.
- Clippy warnings fail CI; fix them rather than allowing them.
