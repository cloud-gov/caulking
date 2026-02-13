#!/usr/bin/env bash
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

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/xdg"
mkdir -p "$HOME" "$XDG_CONFIG_HOME"

repo="$tmp/repo"
mkdir -p "$repo"
cd "$repo"
git init -q
git config user.name "t"
git config user.email "t@gsa.gov"

mkdir -p "$XDG_CONFIG_HOME/gitleaks"
cat > "$XDG_CONFIG_HOME/gitleaks/config.toml" << 'EOF'
title="test"
[extend]
useDefault=true
EOF

hook="$tmp/pre-commit"
cp -f "$WRAPPER_SRC" "$hook"
chmod +x "$hook"

date > blocked.pem
git add blocked.pem

set +e
out="$(SKIP=gitleaks "$hook" 2>&1)"
rc=$?
set -e

echo "$out" | grep -q "forbidden file staged" || {
  echo "missing denylist message"
  echo "$out"
  exit 1
}
echo "$out" | grep -q "blocked.pem" || {
  echo "missing filename"
  echo "$out"
  exit 1
}
[ "$rc" -ne 0 ] || {
  echo "expected failure"
  exit 1
}
