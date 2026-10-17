# app

One line saying what this project is.

## Commands

Run tools through the dev shell: `direnv allow` once, or
`nix develop -c <command>`.

- `nix build`: build the package into `result/`.
- `./ci.sh fmt`: the format check CI runs (`zig fmt --check build.zig src`).
- `./ci.sh test`: the checks CI runs (`zig build test`).

## Rules

- `nix build` runs `zig build` in the sandbox with an empty Zig cache and no
  network. Dependencies in `build.zig.zon` must be supplied to the derivation
  in `flake.nix`, for example with `zig.fetchDeps`.
