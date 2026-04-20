#!/usr/bin/env bash
set -euo pipefail

PLUGINS=(
  kubernetes
  configuration-as-code
  workflow-aggregator
  credentials
  credentials-binding
  job-dsl
  warnings-ng
  junit
  pipeline-utility-steps
  ansicolor
  timestamper
  prometheus
  sse-gateway
)

usage() {
  cat <<'USAGE'
Usage: install-jenkins-plugins.sh [--plugin NAME]...

Installs the default Jenkins plugin baseline or additional plugins via jenkins-plugin-cli.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin)
      PLUGINS+=("$2")
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

if ! command -v jenkins-plugin-cli >/dev/null 2>&1; then
  echo "jenkins-plugin-cli is required. Use the official Jenkins image or install the CLI first." >&2
  exit 1
fi

jenkins-plugin-cli --plugins "${PLUGINS[*]}"
