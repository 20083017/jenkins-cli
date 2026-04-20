#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="$(pwd)"
HEADER_FILTER='.*'
FORCE=0

usage() {
  cat <<'USAGE'
Usage: bootstrap-cpp-quality.sh [--target-dir DIR] [--header-filter REGEX] [--force]

Creates default .clang-format and .clang-tidy files when they do not already exist.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    --header-filter)
      HEADER_FILTER="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

mkdir -p "$TARGET_DIR/artifacts/cpp-quality"

write_file_if_allowed() {
  local path="$1"
  local content="$2"
  if [[ -f "$path" && "$FORCE" -ne 1 ]]; then
    echo "Keeping existing $path"
    return 0
  fi
  printf '%s\n' "$content" > "$path"
  echo "Wrote $path"
}

write_file_if_allowed "$TARGET_DIR/.clang-format" "---
BasedOnStyle: LLVM
IndentWidth: 2
ColumnLimit: 100
SortIncludes: CaseSensitive
PointerAlignment: Left
AllowShortIfStatementsOnASingleLine: Never
..."

write_file_if_allowed "$TARGET_DIR/.clang-tidy" "---
Checks: >
  bugprone-*,
  clang-analyzer-*,
  performance-*,
  portability-*,
  readability-*,
  -readability-magic-numbers,
  -readability-identifier-length
WarningsAsErrors: >
  bugprone-*,
  clang-analyzer-*
HeaderFilterRegex: '$HEADER_FILTER'
FormatStyle: file
AnalyzeTemporaryDtors: false
..."

echo "Bootstrap complete for $TARGET_DIR"
