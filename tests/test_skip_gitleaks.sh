#!/usr/bin/env bash
# Test that SKIP=gitleaks bypasses gitleaks scanning.
# Note: forbidden file blocking still applies even with SKIP=gitleaks.
set -euo pipefail

# shellcheck source=lib/test-helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/test-helpers.sh"

full_test_setup

echo "=== Test 1: Without SKIP, secret should be blocked ==="
echo "aws_secret_access_key = WT8ftNba7siVx5UOoGzJSyd82uNCZAC8LCllzcWp" > secret.txt
git add secret.txt

set +e
"$TEST_HOOK" > /dev/null 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: Secret should have been blocked without SKIP"
  exit 1
fi
echo "PASS: Secret blocked without SKIP"

echo ""
echo "=== Test 2: With SKIP=gitleaks, secret scanning should be bypassed ==="
git reset -q HEAD -- secret.txt 2> /dev/null || true
git add secret.txt

set +e
out="$(SKIP=gitleaks "$TEST_HOOK" 2>&1)"
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  echo "FAIL: With SKIP=gitleaks, commit should have succeeded"
  echo "Output: $out"
  exit 1
fi

if ! echo "$out" | grep -qi "skip.*gitleaks"; then
  echo "FAIL: Expected skip message in output"
  echo "Output: $out"
  exit 1
fi
echo "PASS: SKIP=gitleaks bypassed gitleaks scanning"

echo ""
echo "=== Test 3: SKIP=gitleaks does NOT bypass forbidden file blocking ==="
git reset -q HEAD -- secret.txt 2> /dev/null || true
rm -f secret.txt

echo "not a real key" > test.pem
git add test.pem

set +e
out="$(SKIP=gitleaks "$TEST_HOOK" 2>&1)"
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: Forbidden file should still be blocked even with SKIP=gitleaks"
  exit 1
fi

if ! echo "$out" | grep -q "forbidden file staged"; then
  echo "FAIL: Expected forbidden file message"
  echo "Output: $out"
  exit 1
fi
echo "PASS: Forbidden files still blocked with SKIP=gitleaks"

echo ""
echo "All SKIP=gitleaks tests passed!"
