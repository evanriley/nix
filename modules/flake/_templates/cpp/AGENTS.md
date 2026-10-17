# app

One line saying what this project is.

## Commands

Run tools through the dev shell: `direnv allow` once, or
`nix develop -c <command>`.

- `nix build`: build the package into `result/` and run the Catch2 tests.
- `./ci.sh fmt`: the format check CI runs (`clang-format --dry-run --Werror`
  on every tracked `.cpp` and `.hpp` file).
- `./ci.sh test`: the checks CI runs (the `ci` and `asan` workflows, then the
  fuzz target for 10 seconds).
- `cmake --workflow --preset <preset>`: configure, build and test into
  `build/<preset>/`.

| Preset | Use                                                             |
| ------ | --------------------------------------------------------------- |
| `dev`  | Day-to-day Debug build with standard library assertions.        |
| `ci`   | `dev` with warnings as errors and clang-tidy; run before push.  |
| `asan` | `dev` with AddressSanitizer and UndefinedBehaviorSanitizer.     |
| `tsan` | `dev` with ThreadSanitizer; run locally when touching threads.  |
| `fuzz` | `asan` plus the libFuzzer target; Linux only, mostly local.     |

Run the fuzzer longer than CI does with
`build/fuzz/<name>_fuzz -max_total_time=300` after
`cmake --workflow --preset fuzz`.

## Rules

- C++23 with Clang from `llvmPackages_latest` and libstdc++. No C++ modules or
  `import std` yet.
- Dependencies come from nixpkgs: add them to `buildInputs` in `flake.nix` and
  use them with `find_package`. No FetchContent, Conan or vcpkg.
- Zero warnings. CI builds with `-Werror` and
  `clang-tidy --warnings-as-errors=*`; fix the code instead of disabling a
  check. `nix build` does not use `-Werror`.
- clang-tidy enforces the C++ Core Guidelines and the naming rules in
  `.clang-tidy`: `lower_case` for every identifier.
- Tiger Style:
  - Check invariants with the project's `check()` from `check.hpp`, which stays
    on in Release builds. Use `assert` only for expensive debug-only checks.
  - Put an upper bound on every loop and queue.
  - Allocate at startup; no allocation on the steady-state path.
  - Keep functions at 70 lines or fewer.
  - No recursion; `misc-no-recursion` fails CI.
