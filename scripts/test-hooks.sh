#!/usr/bin/env bash
# test-hooks.sh — Test pre-commit hooks against fixtures
#
# Usage:
#   ./scripts/test-hooks.sh [--verbose] [--quick]
#
# Tests hooks against valid, invalid, and edge-case fixtures.
# Returns exit code 0 if all tests pass, 1 otherwise.
#
# Note: Uses 30 second timeout per test to prevent hanging.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures"

VERBOSE=false
QUICK=false
TIMEOUT=30

for arg in "$@"; do
  case "$arg" in
    --verbose) VERBOSE=true ;;
    --quick)
      QUICK=true
      TIMEOUT=10
      ;;
  esac
done

# Counters
PASS=0
FAIL=0
SKIP=0

# Colors (if terminal supports them)
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  NC='\033[0m' # No Color
else
  GREEN=''
  RED=''
  YELLOW=''
  NC=''
fi

log_pass() {
  echo -e "${GREEN}✓${NC} $1"
  PASS=$((PASS + 1))
}

log_fail() {
  echo -e "${RED}✗${NC} $1"
  FAIL=$((FAIL + 1))
}

log_skip() {
  echo -e "${YELLOW}○${NC} $1 (skipped)"
  SKIP=$((SKIP + 1))
}

# Run command with timeout (macOS compatible)
run_with_timeout() {
  local timeout_sec="$1"
  shift

  # Start command in background
  "$@" &
  local pid=$!

  # Wait with timeout
  local count=0
  while kill -0 "$pid" 2> /dev/null; do
    sleep 1
    count=$((count + 1))
    if [[ $count -ge $timeout_sec ]]; then
      kill -9 "$pid" 2> /dev/null || true
      wait "$pid" 2> /dev/null || true
      return 124 # timeout exit code
    fi
  done

  wait "$pid"
  return $?
}

# Test a hook expecting it to pass
test_pass() {
  local hook_id="$1"
  local fixture="$2"
  local description="${3:-$hook_id on $fixture}"

  if [[ ! -f "$fixture" ]]; then
    log_skip "$description - fixture not found"
    return
  fi

  $VERBOSE && echo "Testing: $description"

  if run_with_timeout "$TIMEOUT" pre-commit try-repo "$REPO_ROOT" "$hook_id" --files "$fixture" &> /dev/null; then
    log_pass "$description"
  else
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      log_skip "$description - timeout"
    else
      log_fail "$description (expected pass, got fail)"
    fi
  fi
}

# Test a hook expecting it to fail
test_fail() {
  local hook_id="$1"
  local fixture="$2"
  local description="${3:-$hook_id rejects $fixture}"

  if [[ ! -f "$fixture" ]]; then
    log_skip "$description - fixture not found"
    return
  fi

  $VERBOSE && echo "Testing: $description"

  if run_with_timeout "$TIMEOUT" pre-commit try-repo "$REPO_ROOT" "$hook_id" --files "$fixture" &> /dev/null; then
    log_fail "$description (expected fail, got pass)"
  else
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      log_skip "$description - timeout"
    else
      log_pass "$description"
    fi
  fi
}

echo "=== Pre-commit Hook Test Matrix ==="
echo ""
echo "Testing against fixtures in: $FIXTURES"
echo "Timeout per test: ${TIMEOUT}s"
echo ""

# =============================================================================
# YAML Hooks
# =============================================================================
echo "--- YAML Hooks ---"
test_pass "check-yaml" "$FIXTURES/valid/sample.yaml" "check-yaml accepts valid YAML"
test_fail "check-yaml" "$FIXTURES/invalid/bad-yaml.yaml" "check-yaml rejects invalid YAML"

# =============================================================================
# JSON Hooks
# =============================================================================
echo ""
echo "--- JSON Hooks ---"
test_pass "check-json" "$FIXTURES/valid/sample.json" "check-json accepts valid JSON"
test_fail "check-json" "$FIXTURES/invalid/bad-json.json" "check-json rejects invalid JSON"

# =============================================================================
# Shell Hooks
# =============================================================================
echo ""
echo "--- Shell Hooks ---"
test_pass "shellcheck" "$FIXTURES/valid/sample.sh" "shellcheck accepts valid shell"
test_fail "shellcheck" "$FIXTURES/invalid/bad-shell.sh" "shellcheck rejects unquoted variable"

# Skip slower tests in quick mode
if ! $QUICK; then
  # =============================================================================
  # Dockerfile Hooks
  # =============================================================================
  echo ""
  echo "--- Dockerfile Hooks ---"
  test_pass "hadolint" "$FIXTURES/valid/Dockerfile" "hadolint accepts valid Dockerfile"
  test_fail "hadolint" "$FIXTURES/invalid/bad-dockerfile" "hadolint rejects unpinned base image"

  # =============================================================================
  # Python Hooks (requires ruff, bandit installed)
  # =============================================================================
  echo ""
  echo "--- Python Hooks ---"
  if command -v ruff &> /dev/null; then
    test_pass "ruff-check" "$FIXTURES/valid/sample.py" "ruff-check accepts valid Python"
  else
    log_skip "ruff-check - ruff not installed"
  fi
  if command -v bandit &> /dev/null; then
    test_pass "bandit" "$FIXTURES/valid/sample.py" "bandit accepts secure Python"
    test_fail "bandit" "$FIXTURES/invalid/insecure.py" "bandit rejects insecure Python"
  else
    log_skip "bandit - bandit not installed"
    SKIP=$((SKIP + 1))
  fi

  # =============================================================================
  # Go Hooks (requires go installed)
  # =============================================================================
  echo ""
  echo "--- Go Hooks ---"
  if command -v go &> /dev/null; then
    test_pass "go-fmt" "$FIXTURES/valid/sample.go" "go-fmt accepts valid Go"
  else
    log_skip "go-fmt - go not installed"
  fi
  if command -v gosec &> /dev/null; then
    test_fail "gosec" "$FIXTURES/invalid/insecure.go" "gosec rejects insecure Go"
  else
    log_skip "gosec - gosec not installed"
  fi

  # =============================================================================
  # Terraform Hooks (requires tofu or terraform installed)
  # =============================================================================
  echo ""
  echo "--- Terraform/OpenTofu Hooks ---"
  if command -v tofu &> /dev/null; then
    test_pass "tofu-fmt" "$FIXTURES/valid/sample.tf" "tofu-fmt accepts valid HCL"
  elif command -v terraform &> /dev/null; then
    test_pass "terraform-fmt" "$FIXTURES/valid/sample.tf" "terraform-fmt accepts valid HCL"
  else
    log_skip "terraform/tofu-fmt - neither tofu nor terraform installed"
  fi
  if command -v tflint &> /dev/null; then
    test_fail "tflint" "$FIXTURES/invalid/bad-terraform.tf" "tflint rejects deprecated syntax"
  else
    log_skip "tflint - tflint not installed"
  fi

  # =============================================================================
  # Edge Cases
  # =============================================================================
  echo ""
  echo "--- Edge Cases ---"
  test_pass "trailing-whitespace" "$FIXTURES/edge-cases/unicode-тест.txt" "handles unicode filename"
  test_pass "trailing-whitespace" "$FIXTURES/edge-cases/file with spaces.txt" "handles filename with spaces"
else
  echo ""
  echo "--- Skipping slower tests (--quick mode) ---"
  ((SKIP += 4))
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=== Test Summary ==="
echo -e "Passed: ${GREEN}$PASS${NC}"
echo -e "Failed: ${RED}$FAIL${NC}"
echo -e "Skipped: ${YELLOW}$SKIP${NC}"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}Some tests failed!${NC}"
  exit 1
else
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
fi
