#!/usr/bin/env bash
# test-validate-hooks.sh — behavioral tests for scripts/validate-hooks.py's
# language-acceptance policy (issue #34).
#
# The repo has no Python test harness; this drives validate-hooks.py against
# generated fixture manifests and asserts the accept/error/note behavior:
#   - system / script / unsupported / unsupported_script  -> ACCEPTED (exit 0)
#   - system / script                                     -> emit a "preferred" NOTE
#   - an unrecognized language (typo)                     -> ERROR (exit 1)
#   - a missing required key                              -> ERROR (exit 1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/validate-hooks.py"

PASS=0
FAIL=0

# validate-hooks.py hardcodes the filename ".pre-commit-hooks.yaml" in main() and
# ignores argv, so each fixture is run from a throwaway dir where it IS that file.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

indent() { printf '%s\n' "$OUT" | while IFS= read -r l; do printf '      %s\n' "$l"; done; }

PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "$PYTHON_BIN" ]]; then
  for candidate in python3 /opt/homebrew/opt/pre-commit/libexec/bin/python /usr/bin/python3; do
    if command -v "$candidate" > /dev/null 2>&1 && "$candidate" -c "import yaml" > /dev/null 2>&1; then
      PYTHON_BIN="$candidate"
      break
    fi
  done
  PYTHON_BIN="${PYTHON_BIN:-python3}"
fi

# run_in DIRFILE -> sets OUT, returns validator exit code
run_in() {
  local d
  d="$(dirname "$1")"
  OUT="$(cd "$d" && "$PYTHON_BIN" "$VALIDATOR" 2>&1)" && return 0 || return $?
}

check_exit() { # check_exit DIRFILE EXPECTED DESC
  local rc=0
  run_in "$1" || rc=$?
  if [ "$rc" -eq "$2" ]; then
    echo "  ok: $3 (exit $rc)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $3 (expected $2, got $rc)"
    indent
    FAIL=$((FAIL + 1))
  fi
}

check_out() { # check_out DIRFILE NEEDLE DESC
  run_in "$1" || true
  if printf '%s' "$OUT" | grep -q -- "$2"; then
    echo "  ok: $3"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $3 (missing: $2)"
    indent
    FAIL=$((FAIL + 1))
  fi
}

mk() { # mk NAME LANGUAGE -> echoes the created manifest path
  local dir="$tmp/$1"
  mkdir -p "$dir"
  cat > "$dir/.pre-commit-hooks.yaml" << EOF
- id: sample
  name: Sample
  description: sample hook
  entry: true
  language: $2
EOF
  printf '%s' "$dir/.pre-commit-hooks.yaml"
}

echo "validate-hooks language policy (#34):"
check_exit "$(mk system system)" 0 "language: system accepted"
check_exit "$(mk script script)" 0 "language: script accepted"
check_exit "$(mk unsupported unsupported)" 0 "language: unsupported accepted"
check_exit "$(mk unsupported_script unsupported_script)" 0 "language: unsupported_script accepted"
check_exit "$(mk golang golang)" 0 "language: golang accepted"
check_exit "$(mk typo golangg)" 1 "unrecognized language errors"
check_out "$tmp/system/.pre-commit-hooks.yaml" "preferred for new hooks" "system emits preferred-note"

# missing required key
missdir="$tmp/missing"
mkdir -p "$missdir"
cat > "$missdir/.pre-commit-hooks.yaml" << 'EOF'
- id: nolang
  name: No language
  entry: true
EOF
check_exit "$missdir/.pre-commit-hooks.yaml" 1 "missing required key errors"

echo ""
echo "validate-hooks tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
