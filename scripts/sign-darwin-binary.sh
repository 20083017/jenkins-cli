#!/usr/bin/env bash
set -euo pipefail

binary_path="${1:?usage: ./scripts/sign-darwin-binary.sh <binary> [target] }"
target="${2:-$(go env GOOS 2>/dev/null || echo unknown)}"
identifier="${MACOS_CODESIGN_IDENTIFIER:-io.github.avivsinai.jk}"

case "$target" in
  *darwin*)
    ;;
  *)
    exit 0
    ;;
esac

if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

if [[ ! -f "$binary_path" ]]; then
  echo "error: binary not found: $binary_path" >&2
  exit 1
fi

codesign --force --sign - --identifier "$identifier" "$binary_path"
codesign --verify --strict --verbose=2 "$binary_path"
