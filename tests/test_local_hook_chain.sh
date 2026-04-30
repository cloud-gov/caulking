#!/usr/bin/env bash
# test_local_hook_chain.sh
#
# Tests that repo-local .git/hooks/pre-commit is executed after global hook.
# Validates hook chaining behavior.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER_SRC="$ROOT/hooks/hook-wrapper.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/caulking.chain.XXXXXX")"
cleanup() {
  rm -rf "$tmp" || true
  rm -f /tmp/caulking_local_hook_marker 2> /dev/null || true
}
trap cleanup EXIT

command -v gitleaks > /dev/null 2>&1 || {
  echo "SKIP: gitleaks not installed"
  exit 0
}

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/xdg"
mkdir -p "$HOME" "$XDG_CONFIG_HOME"

repo="$tmp/repo"
mkdir -p "$repo"
cd "$repo"
git init -q
git config user.name "test"
git config user.email "test@gsa.gov"

# Create gitleaks config
mkdir -p "$XDG_CONFIG_HOME/gitleaks"
cat > "$XDG_CONFIG_HOME/gitleaks/config.toml" << 'EOF'
title="test"
[extend]
useDefault=true
EOF

# Install the hook wrapper as the "global" hook
# We'll run it directly and it will chain to the local hook
hook="$tmp/pre-commit"
cp -f "$WRAPPER_SRC" "$hook"
chmod +x "$hook"

# Create a local hook that writes a marker file
mkdir -p "$repo/.git/hooks"
local_hook="$repo/.git/hooks/pre-commit"
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

# Remove any existing marker
rm -f /tmp/caulking_local_hook_marker

# Ensure no .pre-commit-config.yaml exists (so local hook gets run)
rm -f "$repo/.pre-commit-config.yaml"

# Run the global hook - it should detect the local hook and run it
"$hook" > /dev/null 2>&1

# Check if local hook was executed
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

# Create a local hook that fails
cat > "$local_hook" << 'LOCALHOOK'
#!/usr/bin/env bash
echo "LOCAL_HOOK_FAILED"
exit 1
LOCALHOOK
chmod +x "$local_hook"

set +e
out="$("$hook" 2>&1)"
rc=$?
set -e

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

# Make local hook non-executable
chmod -x "$local_hook"

# Reset to a passing hook content (irrelevant since it won't be executed)
cat > "$local_hook" << 'LOCALHOOK'
#!/usr/bin/env bash
exit 1
LOCALHOOK

set +e
"$hook" > /dev/null 2>&1
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  echo "FAIL: Non-executable local hook should be skipped, not fail"
  exit 1
fi

echo "PASS: Non-executable local hook skipped correctly"

echo ""
echo "All local hook chain tests passed!"
