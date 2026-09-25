let
  template = name: description: steps: {
    path = ./_templates/${name};
    inherit description;
    welcomeText = ''
      # ${description}

      The project is named `app`. To rename it:
      ${steps}
      Then `direnv allow` loads the dev shell, and `nix build` builds `result/bin/`.
    '';
  };
in
{
  flake.templates = {
    rust = template "rust" "Rust with crane" ''
      - Change `name` in `Cargo.toml`; `cargo build` updates `Cargo.lock`.
    '';
    zig = template "zig" "Zig" ''
      - Change `.name` in `build.zig` and `pname` in `flake.nix`.
    '';
    ocaml = template "ocaml" "OCaml with dune" ''
      - Change the package name in `dune-project`, `public_name` in `bin/dune` and `pname` in `flake.nix`.
    '';
    gleam = template "gleam" "Gleam with nix-gleam" ''
      - Change `name` in `gleam.toml`, rename `src/app.gleam` and `test/app_test.gleam`,
        then `gleam build` updates `manifest.toml`.
    '';
    python = template "python" "Python with uv and uv2nix" ''
      - Change `name` and `[project.scripts]` in `pyproject.toml`, rename `src/app/`,
        then `uv lock`.
    '';
    clojure = template "clojure" "Clojure with clj-nix" ''
      - Rename `src/app/`, then change `ns` in `core.clj` and `name`/`main-ns` in `flake.nix`.
      - After any change to `deps.edn`, run `deps-lock` to regenerate `deps-lock.json`.
    '';
  };
}
