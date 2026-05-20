#!/usr/bin/env bash
# test_npmrc_validation.sh - Test .npmrc validation logic

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/fixtures/npmrc-test"
HOOK_WRAPPER="$SCRIPT_DIR/../hooks/hook-wrapper.sh"

# Test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Setup
setup() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
}

# Cleanup
cleanup() {
  rm -rf "$TEST_DIR"
}

# Source the validation function
source_hook_functions() {
  # Define minimal functions needed for testing
  say() { printf "%s\n" "$*"; }

  print_npmrc_hint() {
    cat << 'EOF'
Caulking blocked .npmrc because it may contain auth tokens or lack security controls.
EOF
  }

  # Source the actual validate_npmrc function from hook-wrapper.sh
  # Extract just the validate_npmrc function
  eval "$(sed -n '/^validate_npmrc()/,/^}/p' "$HOOK_WRAPPER")"
}

# Test helper
run_test() {
  local test_name="$1"
  local npmrc_content="$2"
  local expected_exit_code="$3"
  local expected_output_pattern="${4:-}"

  TESTS_RUN=$((TESTS_RUN + 1))

  # Create test .npmrc
  echo "$npmrc_content" > "$TEST_DIR/.npmrc"

  # Run validation
  local output
  local exit_code=0
  output=$(validate_npmrc "$TEST_DIR/.npmrc" 2>&1) || exit_code=$?

  # Check exit code
  if [[ $exit_code -ne $expected_exit_code ]]; then
    echo -e "${RED}✗ FAIL${NC}: $test_name"
    echo "  Expected exit code: $expected_exit_code"
    echo "  Actual exit code: $exit_code"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi

  # Check output pattern if provided
  if [[ -n "$expected_output_pattern" ]]; then
    if ! echo "$output" | grep -q "$expected_output_pattern"; then
      echo -e "${RED}✗ FAIL${NC}: $test_name"
      echo "  Expected output to contain: $expected_output_pattern"
      echo "  Actual output: $output"
      TESTS_FAILED=$((TESTS_FAILED + 1))
      return 1
    fi
  fi

  echo -e "${GREEN}✓ PASS${NC}: $test_name"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  return 0
}

# Test cases
test_safe_npmrc_with_security_controls() {
  run_test "Safe .npmrc with security controls" \
    "ignore-scripts=true
audit=true
fund=false" \
    0
}

test_safe_npmrc_without_security_controls() {
  run_test "Safe .npmrc without security controls (should warn)" \
    "fund=false
audit=true" \
    0 \
    "WARNING.*ignore-scripts"
}

test_unsafe_npmrc_with_authtoken() {
  run_test "Unsafe .npmrc with _authToken" \
    "_authToken=npm_abc123456789" \
    1 \
    "ERROR.*auth tokens"
}

test_unsafe_npmrc_with_auth_base64() {
  run_test "Unsafe .npmrc with _auth (base64)" \
    "//registry.npmjs.org/:_auth=dGVzdDp0ZXN0" \
    1 \
    "ERROR.*auth tokens"
}

test_unsafe_npmrc_with_scoped_token() {
  run_test "Unsafe .npmrc with scoped token" \
    "@myorg:registry=https://npm.myorg.com/
//npm.myorg.com/:_authToken=npm_secret123" \
    1 \
    "ERROR.*auth tokens"
}

test_safe_npmrc_with_registry_config() {
  run_test "Safe .npmrc with registry configuration" \
    "registry=https://registry.npmjs.org/
@myorg:registry=https://npm.myorg.com/" \
    0
}

test_safe_npmrc_with_environment_variable_reference() {
  run_test "Safe .npmrc with env var reference (no actual token)" \
    "ignore-scripts=true
# Token should be in ~/.npmrc: \${NPM_TOKEN}" \
    0
}

test_empty_npmrc() {
  run_test "Empty .npmrc file" \
    "" \
    0
}

# Main
main() {
  echo "========================================="
  echo "Testing .npmrc validation logic"
  echo "========================================="
  echo ""

  setup
  source_hook_functions

  # Run all tests
  test_safe_npmrc_with_security_controls
  test_safe_npmrc_without_security_controls
  test_unsafe_npmrc_with_authtoken
  test_unsafe_npmrc_with_auth_base64
  test_unsafe_npmrc_with_scoped_token
  test_safe_npmrc_with_registry_config
  test_safe_npmrc_with_environment_variable_reference
  test_empty_npmrc

  cleanup

  # Summary
  echo ""
  echo "========================================="
  echo "Test Summary"
  echo "========================================="
  echo "Tests run:    $TESTS_RUN"
  echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
  if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    exit 1
  else
    echo "Tests failed: 0"
    echo ""
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
  fi
}

main "$@"
