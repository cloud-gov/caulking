#!/usr/bin/env bash
# test_skip_gitleaks.sh
#
# Tests that SKIP=gitleaks actually bypasses gitleaks scanning.
# Note: forbidden file blocking still applies even with SKIP=gitleaks.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER_SRC="$ROOT/hooks/hook-wrapper.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/caulking.skip.XXXXXX")"
cleanup() { rm -rf "$tmp" || true; }
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

hook="$tmp/pre-commit"
cp -f "$WRAPPER_SRC" "$hook"
chmod +x "$hook"

echo "=== Test 1: Without SKIP, secret should be blocked ==="
echo "aws_secret_access_key = WT8ftNba7siVx5UOoGzJSyd82uNCZAC8LCllzcWp" > secret.txt
git add secret.txt

set +e
"$hook" > /dev/null 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: Secret should have been blocked without SKIP"
  exit 1
fi
echo "PASS: Secret blocked without SKIP"

echo ""
echo "=== Test 2: With SKIP=gitleaks, secret scanning should be bypassed ==="
# Reset staging
git reset -q HEAD -- secret.txt 2> /dev/null || true

# Stage again
git add secret.txt

set +e
out="$(SKIP=gitleaks "$hook" 2>&1)"
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

# Create a forbidden file type
echo "not a real key" > test.pem
git add test.pem

set +e
out="$(SKIP=gitleaks "$hook" 2>&1)"
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
