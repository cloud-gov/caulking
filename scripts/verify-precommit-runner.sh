#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib.sh"

on_err_trap
enable_xtrace_if_debug

cd "$ROOT"

# Only relevant if this repo actually uses pre-commit config
if [[ ! -f ".pre-commit-config.yaml" ]]; then
  info "OK: no .pre-commit-config.yaml in repo; skipping pre-commit runner check"
  exit 0
fi

# Deterministic/offline by default:
# - Validate config format only (no hook env init, no cloning)
# If you *want* to force an execution smoke-test, set:
#   CAULKING_VERIFY_PRECOMMIT_EXEC=1
EXEC="${CAULKING_VERIFY_PRECOMMIT_EXEC:-0}"

if have prek; then
  info "Found prek: $(command -v prek)"

  if [[ "$EXEC" == "1" ]]; then
    info "Executing repo hooks via prek (CAULKING_VERIFY_PRECOMMIT_EXEC=1)"
    prek run --hook-stage pre-commit --all-files --show-diff-on-failure || die "prek failed to execute repo hooks"
  else
    info "OK: prek present (execution smoke-test skipped; set CAULKING_VERIFY_PRECOMMIT_EXEC=1 to run hooks)"
  fi

  exit 0
fi

if have pre-commit; then
  info "Found pre-commit: $(command -v pre-commit)"

  # Offline/deterministic: validate config only
  pre-commit validate-config .pre-commit-config.yaml || die "pre-commit config validation failed"

  if [[ "$EXEC" == "1" ]]; then
    info "Executing repo hooks via pre-commit (CAULKING_VERIFY_PRECOMMIT_EXEC=1)"
    # NOTE: This may require network on first run to initialize hook environments.
    pre-commit run --hook-stage pre-commit --all-files --show-diff-on-failure || die "pre-commit failed to execute repo hooks"
  else
    info "OK: pre-commit config validated (execution smoke-test skipped; set CAULKING_VERIFY_PRECOMMIT_EXEC=1 to run hooks)"
  fi

  exit 0
fi

# In CI environments without prek/pre-commit, this is acceptable since
# pre-commit tooling is for developer workflow, not caulking's core functionality.
# The .pre-commit-config.yaml is for linting THIS repo, not for caulking's users.
if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" || "${GITLAB_CI:-}" == "true" ]]; then
  warn "Repo has .pre-commit-config.yaml but neither prek nor pre-commit is installed (CI environment - skipping)"
  exit 0
fi

die "Repo has .pre-commit-config.yaml but neither prek nor pre-commit is installed"
