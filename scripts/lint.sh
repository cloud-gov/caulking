#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib.sh"

on_err_trap
enable_xtrace_if_debug

cd "$ROOT"

info "== Lint (repo hooks) =="

if [[ ! -f ".pre-commit-config.yaml" ]]; then
  die "No .pre-commit-config.yaml found. Nothing to lint via repo hook suite."
fi

# Allow skip in CI or local workflows if needed.
if [[ "${CAULKING_SKIP_LINT:-0}" == "1" ]]; then
  warn "CAULKING_SKIP_LINT=1; skipping lint."
  exit 0
fi

if have prek; then
  info "Using prek: $(command -v prek)"
  # This may fetch hook envs on first run (expected for pre-commit ecosystems).
  prek run --all-files --show-diff-on-failure
  exit 0
fi

if have pre-commit; then
  info "Using pre-commit: $(command -v pre-commit)"
  pre-commit run --all-files --show-diff-on-failure
  exit 0
fi

die "Neither prek nor pre-commit is installed. Install one (preferred: prek) to run lint."
