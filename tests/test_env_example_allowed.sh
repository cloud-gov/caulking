#!/usr/bin/env bash
# Test .env.example/.sample/.template files ALLOWED, .env/.env.local BLOCKED
# Fixes: https://github.com/cloud-gov/caulking/issues/109
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER_SRC="$ROOT/hooks/hook-wrapper.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/caulking.test.XXXXXX")"
cleanup() { rm -rf "$tmp" || true; }
trap cleanup EXIT

command -v gitleaks > /dev/null 2>&1 || {
  echo "SKIP: gitleaks not installed"
  exit 0
}

export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/xdg"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/gitleaks"
cat > "$XDG_CONFIG_HOME/gitleaks/config.toml" << 'EOF'
title="test"
[extend]
useDefault=true
EOF

repo="$tmp/repo"
mkdir -p "$repo" && cd "$repo"
git init -q && git config user.name "t" && git config user.email "t@gsa.gov"

hook="$tmp/pre-commit"
cp -f "$WRAPPER_SRC" "$hook" && chmod +x "$hook"

# Helper: test file allowed/blocked
test_file() {
  local file="$1" expect="$2" content="${3:-test}"
  mkdir -p "$(dirname "$file")" 2> /dev/null || true
  echo "$content" > "$file"
  git add "$file"
  set +e
  out="$("$hook" 2>&1)"
  rc=$?
  set -e
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
