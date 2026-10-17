#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

case "${1:-}" in
  fmt)
    nix develop -c ruff format --check
    ;;
  test)
    nix develop -c ruff check
    nix develop -c basedpyright
    ;;
  *)
    echo "unknown phase '${1:-}': expected fmt or test" >&2
    exit 2
    ;;
esac
