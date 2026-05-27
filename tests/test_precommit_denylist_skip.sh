#!/usr/bin/env bash
# Test that denylist still blocks even with SKIP=gitleaks
set -euo pipefail

# shellcheck source=lib/test-helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/test-helpers.sh"

full_test_setup

# Stage forbidden file type
date > blocked.pem
git add blocked.pem

set +e
out="$(SKIP=gitleaks "$TEST_HOOK" 2>&1)"
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
