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

# Deterministic/offline by default:
# - Validate config format only (no hook env init, no cloning)
# If you *want* to force an execution smoke-test, set:
#   CAULKING_VERIFY_PRECOMMIT_EXEC=1
EXEC="${CAULKING_VERIFY_PRECOMMIT_EXEC:-0}"

if have prek; then
  say "Found prek: $(command -v prek)"

  # prek compatibility: we at least validate that it can read the config.
  # If prek ever adds a dedicated validate command, use it here.
  # For now, config validation is best-effort by checking command availability.
  if [[ "$EXEC" == "1" ]]; then
    say "Executing repo hooks via prek (CAULKING_VERIFY_PRECOMMIT_EXEC=1)"
    if ! prek run --hook-stage pre-commit --all-files --show-diff-on-failure; then
      die "prek failed to execute repo hooks"
    fi
  else
    say "OK: prek present (execution smoke-test skipped; set CAULKING_VERIFY_PRECOMMIT_EXEC=1 to run hooks)"
  fi

  exit 0
fi

if have pre-commit; then
  say "Found pre-commit: $(command -v pre-commit)"

  # Offline/deterministic: validate config only
  if ! pre-commit validate-config .pre-commit-config.yaml; then
    die "pre-commit config validation failed"
  fi

  if [[ "$EXEC" == "1" ]]; then
    say "Executing repo hooks via pre-commit (CAULKING_VERIFY_PRECOMMIT_EXEC=1)"
    # NOTE: This may require network on first run to initialize hook environments.
    if ! pre-commit run --hook-stage pre-commit --all-files --show-diff-on-failure; then
      die "pre-commit failed to execute repo hooks"
    fi
  else
    say "OK: pre-commit config validated (execution smoke-test skipped; set CAULKING_VERIFY_PRECOMMIT_EXEC=1 to run hooks)"
  fi

  exit 0
fi

die "Repo has .pre-commit-config.yaml but neither prek nor pre-commit is installed"
