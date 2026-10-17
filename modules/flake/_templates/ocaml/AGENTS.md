# app

One line saying what this project is.

## Commands

Run tools through the dev shell: `direnv allow` once, or
`nix develop -c <command>`.

- `nix build`: build the package into `result/`.
- `./ci.sh fmt`: the format check CI runs (`dune build @fmt`).
- `./ci.sh test`: the checks CI runs (`dune test`).

## Rules

- Libraries come from `pkgs.ocamlPackages`, not opam. Add each one to
  `buildInputs` of the package in `flake.nix`; the dev shell inherits it.
