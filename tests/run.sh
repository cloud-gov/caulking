#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0

run_with_timeout() {
  local seconds="$1"
  shift

  if command -v gtimeout > /dev/null 2>&1; then
    gtimeout "${seconds}s" "$@"
    return $?
  fi

  if command -v timeout > /dev/null 2>&1; then
    timeout "${seconds}s" "$@"
    return $?
  fi

  "$@"
}

for t in tests/test_*.sh; do
  echo "== $t =="

  if run_with_timeout 30 bash "$t"; then
    echo "PASS: $t"
  else
    rc=$?
    if [[ "$rc" -eq 124 ]]; then
      echo "FAIL: $t (timed out)"
    else
      echo "FAIL: $t"
    fi
    fail=1
  fi

  echo
done

exit "$fail"
