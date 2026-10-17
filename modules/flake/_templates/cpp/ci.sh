#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

case "${1:-}" in
  fmt)
    mapfile -d '' files < <(git ls-files -z -- '*.cpp' '*.hpp')
    wait $!
    [ ${#files[@]} -eq 0 ] || nix develop -c clang-format --dry-run --Werror -- "${files[@]}"
    ;;
  test)
    nix develop -c cmake --workflow --preset ci
    nix develop -c cmake --workflow --preset asan
    nix develop -c cmake --workflow --preset fuzz
    nix develop -c build/fuzz/app_fuzz -max_total_time=10
    ;;
  *)
    echo "unknown phase '${1:-}': expected fmt or test" >&2
    exit 2
    ;;
esac
