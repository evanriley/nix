#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

case "${1:-}" in
  fmt)
    nix develop -c gleam format --check
    ;;
  test)
    nix develop -c gleam test
    ;;
  *)
    echo "unknown phase '${1:-}': expected fmt or test" >&2
    exit 2
    ;;
esac
