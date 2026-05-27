#!/usr/bin/env bash
# Test proper error handling when gitleaks is not in PATH
set -euo pipefail

# shellcheck source=lib/test-helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/test-helpers.sh"

# Manual setup - we DON'T want require_gitleaks() here since we're testing missing gitleaks
test_init
isolate_env
create_test_repo
create_gitleaks_config
install_hook

# Stage a clean file
echo "clean content" > clean.txt
git add clean.txt

echo "=== Test: gitleaks not in PATH should produce clear error ==="

# Create restricted PATH with only essential commands but NOT gitleaks
restricted_path="$TEST_TMP/bin"
mkdir -p "$restricted_path"

# Create wrapper scripts for required commands
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

# Need bash itself for shebang
bash_path="$(command -v bash)"
cat > "$restricted_path/bash" << WRAPPER
#!/bin/bash
exec "$bash_path" "\$@"
WRAPPER
chmod +x "$restricted_path/bash"

set +e
out="$(PATH="$restricted_path" bash "$TEST_HOOK" 2>&1)"
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
