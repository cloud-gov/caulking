#!/usr/bin/env bash
# Test .env.example/.sample/.template files ALLOWED, .env/.env.local BLOCKED
# Fixes: https://github.com/cloud-gov/caulking/issues/109
set -euo pipefail

# shellcheck source=lib/test-helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/test-helpers.sh"

full_test_setup

# Helper: test file allowed/blocked
test_file() {
  local file="$1" expect="$2" content="${3:-test}"
  mkdir -p "$(dirname "$file")" 2> /dev/null || true
  echo "$content" > "$file"
  git add "$file"
  # Run hook and capture exit code
  "$TEST_HOOK" > /dev/null 2>&1 && rc=0 || rc=$?
  git rm --cached "$file" > /dev/null 2>&1 || true
  if [ "$expect" = "allow" ] && [ "$rc" -ne 0 ]; then
    echo "FAIL: $file blocked (expected allow)"
    exit 1
  elif [ "$expect" = "block" ] && [ "$rc" -eq 0 ]; then
    echo "FAIL: $file allowed (expected block)"
    exit 1
  fi
  echo "PASS: $file ${expect}ed"
}

# Allowed patterns
test_file ".env.example" allow
test_file ".env.local.example" allow
test_file ".env.sample" allow
test_file ".env.template" allow
test_file "config/.env.example" allow

# Blocked patterns
test_file ".env" block
test_file ".env.local" block
test_file ".env.production" block

echo "All tests passed!"
