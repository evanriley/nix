#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

case "${1:-}" in
  fmt)
    nix develop -c zig fmt --check build.zig src
    ;;
  test)
    nix develop -c zig build test
    ;;
  *)
    echo "unknown phase '${1:-}': expected fmt or test" >&2
    exit 2
    ;;
esac
