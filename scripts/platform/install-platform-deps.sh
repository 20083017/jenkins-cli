#!/usr/bin/env bash
set -euo pipefail

MODE="quality"

usage() {
  cat <<'USAGE'
Usage: install-platform-deps.sh [--mode quality|platform]

Installs baseline tooling for C++ quality checks and, optionally, platform CLIs.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
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

if [[ "$MODE" != "quality" && "$MODE" != "platform" ]]; then
  echo "Unsupported mode: $MODE" >&2
  exit 2
fi

OS="$(uname -s)"

install_with_apt() {
  local packages=(git jq cmake ninja-build clang-format clang-tidy)
  sudo apt-get update
  sudo apt-get install -y "${packages[@]}"
  if [[ "$MODE" == "platform" ]]; then
    cat <<'EOFMSG'
Install kubectl and helm from their official apt repositories if they are not already baked into the agent image.
EOFMSG
  fi
}

install_with_dnf() {
  local packages=(git jq cmake ninja-build clang-tools-extra)
  sudo dnf install -y "${packages[@]}"
  if [[ "$MODE" == "platform" ]]; then
    cat <<'EOFMSG'
Install kubectl and helm from their official rpm repositories if they are not already baked into the agent image.
EOFMSG
  fi
}

install_with_brew() {
  local packages=(git jq cmake ninja llvm)
  if [[ "$MODE" == "platform" ]]; then
    packages+=(kubectl helm)
  fi
  brew update
  brew install "${packages[@]}"
  local llvm_prefix
  llvm_prefix="$(brew --prefix llvm 2>/dev/null || true)"
  if [[ -n "$llvm_prefix" ]]; then
    cat <<EOFMSG
Add LLVM tools to PATH if needed:
  export PATH="$llvm_prefix/bin:\$PATH"
EOFMSG
  fi
}

case "$OS" in
  Linux)
    if command -v apt-get >/dev/null 2>&1; then
      install_with_apt
    elif command -v dnf >/dev/null 2>&1; then
      install_with_dnf
    else
      echo "Unsupported Linux package manager. Install git jq cmake ninja clang-format clang-tidy manually." >&2
      exit 1
    fi
    ;;
  Darwin)
    if ! command -v brew >/dev/null 2>&1; then
      echo "Homebrew is required on macOS. Install brew first." >&2
      exit 1
    fi
    install_with_brew
    ;;
  *)
    echo "Unsupported OS: $OS" >&2
    exit 1
    ;;
esac

echo "Installed dependencies for mode: $MODE"
