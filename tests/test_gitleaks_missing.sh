#!/usr/bin/env bash
# test_gitleaks_missing.sh
#
# Tests proper error handling when gitleaks is not in PATH.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER_SRC="$ROOT/hooks/hook-wrapper.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/caulking.missing.XXXXXX")"
cleanup() { rm -rf "$tmp" || true; }
trap cleanup EXIT

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/xdg"
mkdir -p "$HOME" "$XDG_CONFIG_HOME"

repo="$tmp/repo"
mkdir -p "$repo"
cd "$repo"
git init -q
git config user.name "test"
git config user.email "test@gsa.gov"

# Create gitleaks config (hook checks for this before running gitleaks)
mkdir -p "$XDG_CONFIG_HOME/gitleaks"
cat > "$XDG_CONFIG_HOME/gitleaks/config.toml" << 'EOF'
title="test"
[extend]
useDefault=true
EOF

hook="$tmp/pre-commit"
cp -f "$WRAPPER_SRC" "$hook"
chmod +x "$hook"

# Stage a clean file
echo "clean content" > clean.txt
git add clean.txt

echo "=== Test: gitleaks not in PATH should produce clear error ==="

# Create a restricted PATH with only essential commands but NOT gitleaks
# We need to ensure bash and basic utils are available
restricted_path="$tmp/bin"
mkdir -p "$restricted_path"

# Create wrapper scripts that call the real binaries
# This avoids symlink issues on some systems
for cmd in git basename cat mkdir rm printf grep awk tr date readlink dirname command env; do
  cmd_path="$(command -v "$cmd" 2> /dev/null || true)"
  if [[ -n "$cmd_path" && -x "$cmd_path" ]]; then
    cat > "$restricted_path/$cmd" << WRAPPER
#!/bin/bash
exec "$cmd_path" "\$@"
WRAPPER
    chmod +x "$restricted_path/$cmd"
  fi
done

# We need bash itself in the path for the shebang to work
bash_path="$(command -v bash)"
cat > "$restricted_path/bash" << WRAPPER
#!/bin/bash
exec "$bash_path" "\$@"
WRAPPER
chmod +x "$restricted_path/bash"

set +e
out="$(PATH="$restricted_path" bash "$hook" 2>&1)"
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: Hook should fail when gitleaks is missing"
  exit 1
fi

if ! echo "$out" | grep -qi "gitleaks not found"; then
  echo "FAIL: Expected 'gitleaks not found' error message"
  echo "Output: $out"
  exit 1
fi

echo "PASS: Missing gitleaks produces clear error (exit code $rc)"

echo ""
echo "All missing gitleaks tests passed!"
