#!/usr/bin/env bash
# Test that repo-local .git/hooks/pre-commit is executed after global hook
set -euo pipefail

# shellcheck source=lib/test-helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/test-helpers.sh"

full_test_setup

# Cleanup marker file on exit
cleanup_marker() { rm -f /tmp/caulking_local_hook_marker 2> /dev/null || true; }
trap cleanup_marker EXIT

# Create a local hook that writes a marker file
mkdir -p "$TEST_REPO/.git/hooks"
local_hook="$TEST_REPO/.git/hooks/pre-commit"
cat > "$local_hook" << 'LOCALHOOK'
#!/usr/bin/env bash
echo "LOCAL_HOOK_EXECUTED" > /tmp/caulking_local_hook_marker
exit 0
LOCALHOOK
chmod +x "$local_hook"

# Stage a clean file
echo "clean content" > clean.txt
git add clean.txt

echo "=== Test 1: Local hook should be chained after global hook ==="
rm -f /tmp/caulking_local_hook_marker
rm -f "$TEST_REPO/.pre-commit-config.yaml"

"$TEST_HOOK" > /dev/null 2>&1

if [[ ! -f /tmp/caulking_local_hook_marker ]]; then
  echo "FAIL: Local hook was not executed"
  exit 1
fi

marker_content="$(cat /tmp/caulking_local_hook_marker)"
if [[ "$marker_content" != "LOCAL_HOOK_EXECUTED" ]]; then
  echo "FAIL: Local hook marker has wrong content: $marker_content"
  exit 1
fi

rm -f /tmp/caulking_local_hook_marker
echo "PASS: Local hook was chained correctly"

echo ""
echo "=== Test 2: Failing local hook should propagate failure ==="
cat > "$local_hook" << 'LOCALHOOK'
#!/usr/bin/env bash
echo "LOCAL_HOOK_FAILED"
exit 1
LOCALHOOK
chmod +x "$local_hook"

out="$("$TEST_HOOK" 2>&1)" && rc=0 || rc=$?

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: Failing local hook should cause overall failure"
  exit 1
fi

if ! echo "$out" | grep -q "LOCAL_HOOK_FAILED"; then
  echo "FAIL: Local hook output not captured"
  echo "Output: $out"
  exit 1
fi
echo "PASS: Failing local hook propagates failure correctly"

echo ""
echo "=== Test 3: Non-executable local hook should be skipped ==="
chmod -x "$local_hook"
cat > "$local_hook" << 'LOCALHOOK'
#!/usr/bin/env bash
exit 1
LOCALHOOK

"$TEST_HOOK" > /dev/null 2>&1 && rc=0 || rc=$?

if [[ "$rc" -ne 0 ]]; then
  echo "FAIL: Non-executable local hook should be skipped, not fail"
  exit 1
fi
echo "PASS: Non-executable local hook skipped correctly"

echo ""
echo "All local hook chain tests passed!"
