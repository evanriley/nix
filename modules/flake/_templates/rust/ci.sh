#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

case "${1:-}" in
  fmt)
    nix develop -c cargo fmt --check
    ;;
  test)
    nix develop -c cargo clippy -- -D warnings
    nix develop -c cargo test
    ;;
  *)
    echo "unknown phase '${1:-}': expected fmt or test" >&2
    exit 2
    ;;
esac
