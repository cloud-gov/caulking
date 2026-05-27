#!/usr/bin/env bash
# tests/lib/test-helpers.sh - Shared test utilities for caulking test suite
# shellcheck disable=SC2034  # Variables are used by sourcing scripts

set -euo pipefail

# Paths set by test_init()
TEST_ROOT=""
TEST_TMP=""
TEST_REPO=""
TEST_HOOK=""
WRAPPER_SRC=""

# Initialize test environment
# Sets: TEST_ROOT, WRAPPER_SRC, TEST_TMP
# Creates temp dir with cleanup trap
test_init() {
  # Get repo root by finding where hooks/hook-wrapper.sh exists
  # We need to go up from tests/lib/ to the repo root
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  TEST_ROOT="$(cd "$script_dir/../.." && pwd)"
  WRAPPER_SRC="$TEST_ROOT/hooks/hook-wrapper.sh"
  TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/caulking.test.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$TEST_TMP' || true" EXIT
}

# Skip test if gitleaks not installed
require_gitleaks() {
  command -v gitleaks > /dev/null 2>&1 || {
    echo "SKIP: gitleaks not installed"
    exit 0
  }
}

# Isolate HOME and XDG environment
# Sets: HOME, XDG_CONFIG_HOME
isolate_env() {
  export HOME="$TEST_TMP/home"
  export XDG_CONFIG_HOME="$TEST_TMP/xdg"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME"
}

# Create test git repository
# Sets: TEST_REPO, changes to repo directory
create_test_repo() {
  TEST_REPO="$TEST_TMP/repo"
  mkdir -p "$TEST_REPO"
  cd "$TEST_REPO"
  git init -q
  git config user.name "test"
  git config user.email "test@gsa.gov"
}

# Create minimal gitleaks config
create_gitleaks_config() {
  mkdir -p "$XDG_CONFIG_HOME/gitleaks"
  cat > "$XDG_CONFIG_HOME/gitleaks/config.toml" << 'EOF'
title="test"
[extend]
useDefault=true
EOF
}

# Install hook wrapper to test location
# Sets: TEST_HOOK
install_hook() {
  local stage="${1:-pre-commit}"
  TEST_HOOK="$TEST_TMP/$stage"
  cp -f "$WRAPPER_SRC" "$TEST_HOOK"
  chmod +x "$TEST_HOOK"
}

# Full test setup - convenience wrapper
# Calls: test_init, require_gitleaks, isolate_env, create_test_repo, create_gitleaks_config, install_hook
# Sets: TEST_TMP, TEST_REPO, TEST_HOOK
full_test_setup() {
  local stage="${1:-pre-commit}"
  test_init
  require_gitleaks
  isolate_env
  create_test_repo
  create_gitleaks_config
  install_hook "$stage"
}
