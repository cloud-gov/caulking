#!/usr/bin/env bash
set -euo pipefail

say() { printf "%s\n" "$*"; }
die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 2
}
have() { command -v "$1" > /dev/null 2>&1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Only relevant if this repo actually uses pre-commit config
if [[ ! -f ".pre-commit-config.yaml" ]]; then
  say "OK: no .pre-commit-config.yaml in repo; skipping pre-commit runner check"
  exit 0
fi

if have prek; then
  say "Found prek: $(command -v prek)"
  # Validate that prek can parse and execute config in no-op mode
  # --all-files avoids staged-only logic; --hook-stage matches wrapper usage
  prek run --hook-stage pre-commit --all-files > /dev/null 2>&1 || die "prek failed to run .pre-commit-config.yaml"
  say "OK: prek can execute pre-commit config"
  exit 0
fi

if have pre-commit; then
  say "Found pre-commit: $(command -v pre-commit)"
  pre-commit run --hook-stage pre-commit --all-files > /dev/null 2>&1 || die "pre-commit failed to run .pre-commit-config.yaml"
  say "OK: pre-commit can execute pre-commit config"
  exit 0
fi

die "Repo has .pre-commit-config.yaml but neither prek nor pre-commit is installed"
