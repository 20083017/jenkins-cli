#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(pwd)"
BUILD_DIR="$(pwd)/build/ci"
CMAKE_GENERATOR="Ninja"
CMAKE_BUILD_TYPE="RelWithDebInfo"
FILES=()

usage() {
  cat <<'USAGE'
Usage: check-cpp-quality.sh [--source-dir DIR] [--build-dir DIR] [--cmake-generator NAME] [--cmake-build-type TYPE] [--files "a.cpp b.cpp"]

Runs clang-format drift detection and clang-tidy using compile_commands.json.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dir)
      SOURCE_DIR="$2"
      shift 2
      ;;
    --build-dir)
      BUILD_DIR="$2"
      shift 2
      ;;
    --cmake-generator)
      CMAKE_GENERATOR="$2"
      shift 2
      ;;
    --cmake-build-type)
      CMAKE_BUILD_TYPE="$2"
      shift 2
      ;;
    --files)
      IFS=' ' read -r -a FILES <<< "$2"
      shift 2
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

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd clang-format
require_cmd clang-tidy
require_cmd cmake

REPORT_DIR="$SOURCE_DIR/artifacts/cpp-quality"
mkdir -p "$REPORT_DIR"
FORMAT_REPORT="$REPORT_DIR/format-report.txt"
TIDY_REPORT="$REPORT_DIR/tidy-report.txt"
FORMATTED_FILES="$REPORT_DIR/formatted-files.txt"
COMPILE_DB_PATH="$REPORT_DIR/compile-commands-path.txt"

if [[ ${#FILES[@]} -eq 0 ]]; then
  if git -C "$SOURCE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    while IFS= read -r file; do
      FILES+=("$file")
    done < <(git -C "$SOURCE_DIR" ls-files '*.c' '*.cc' '*.cpp' '*.cxx' '*.h' '*.hh' '*.hpp' '*.hxx')
  fi
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  while IFS= read -r file; do
    FILES+=("$file")
  done < <(find "$SOURCE_DIR" -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.cxx' -o -name '*.h' -o -name '*.hh' -o -name '*.hpp' -o -name '*.hxx' \) -print | sed "s|^$SOURCE_DIR/||")
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No C/C++ files found" | tee "$FORMAT_REPORT"
  : > "$TIDY_REPORT"
  : > "$FORMATTED_FILES"
  exit 0
fi

COMPILE_COMMANDS="$BUILD_DIR/compile_commands.json"
if [[ ! -f "$COMPILE_COMMANDS" ]]; then
  if [[ ! -f "$SOURCE_DIR/CMakeLists.txt" ]]; then
    echo "Missing $SOURCE_DIR/CMakeLists.txt and no pre-generated compile_commands.json at $COMPILE_COMMANDS" >&2
    exit 1
  fi
  cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" -G "$CMAKE_GENERATOR" -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON >/dev/null
fi

if [[ ! -f "$COMPILE_COMMANDS" ]]; then
  echo "compile_commands.json was not generated at $COMPILE_COMMANDS" >&2
  exit 1
fi
printf '%s\n' "$COMPILE_COMMANDS" > "$COMPILE_DB_PATH"

: > "$FORMAT_REPORT"
: > "$FORMATTED_FILES"
for file in "${FILES[@]}"; do
  full_path="$SOURCE_DIR/$file"
  if [[ ! -f "$full_path" ]]; then
    continue
  fi
  if ! clang-format --dry-run --Werror "$full_path" >>"$FORMAT_REPORT" 2>&1; then
    printf '%s\n' "$file" >> "$FORMATTED_FILES"
  fi
done

if [[ -s "$FORMATTED_FILES" ]]; then
  echo "clang-format detected formatting drift:" >&2
  cat "$FORMATTED_FILES" >&2
  exit 1
fi

: > "$TIDY_REPORT"
TIDY_TARGETS=()
for file in "${FILES[@]}"; do
  case "$file" in
    *.c|*.cc|*.cpp|*.cxx)
      TIDY_TARGETS+=("$SOURCE_DIR/$file")
      ;;
  esac
done

if [[ ${#TIDY_TARGETS[@]} -eq 0 ]]; then
  echo "No compilable C/C++ source files found for clang-tidy" | tee "$TIDY_REPORT"
  exit 0
fi

clang-tidy -p "$BUILD_DIR" "${TIDY_TARGETS[@]}" | tee "$TIDY_REPORT"
