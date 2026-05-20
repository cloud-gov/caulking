#!/usr/bin/env bash
# Quick health check for caulking installation
# Usage: make status
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/lib.sh"
# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/pretty.sh"

# Load standard XDG paths
eval "$(caulking_export_paths)"

# Track overall status
STATUS_OK=true

check_item() {
  local name="$1"
  local ok="$2"
  local detail="${3:-}"

  if [[ "$ok" == "true" ]]; then
    printf "  %b%-20s%b %b%s%b\n" "$GREEN" "$name" "$RESET" "$GRAY" "$detail" "$RESET"
  else
    printf "  %b%-20s%b %b%s%b\n" "$RED" "$name" "$RESET" "$GRAY" "$detail" "$RESET"
    STATUS_OK=false
  fi
}

printf '\n%b== Caulking Status ==%b\n\n' "$BOLD" "$RESET"

# 1. Check gitleaks
if have gitleaks; then
  gl_version="$(gitleaks version 2> /dev/null | head -n1 || echo 'unknown')"
  check_item "gitleaks" "true" "$gl_version"
else
  check_item "gitleaks" "false" "not found in PATH"
fi

# 2. Check global hooksPath
hookspath="$(git config --global core.hooksPath 2> /dev/null || true)"
if [[ "$hookspath" == "$HOOK_DIR" ]]; then
  check_item "core.hooksPath" "true" "$hookspath"
elif [[ -n "$hookspath" ]]; then
  check_item "core.hooksPath" "false" "set to '$hookspath' (expected: $HOOK_DIR)"
else
  check_item "core.hooksPath" "false" "not set"
fi

# 3. Check pre-commit hook
if [[ -x "$HOOK_DIR/pre-commit" ]]; then
  check_item "pre-commit hook" "true" "installed"
else
  check_item "pre-commit hook" "false" "missing or not executable"
fi

# 4. Check pre-push hook
if [[ -x "$HOOK_DIR/pre-push" ]]; then
  check_item "pre-push hook" "true" "installed"
else
  check_item "pre-push hook" "false" "missing or not executable"
fi

# 5. Check gitleaks config
if [[ -f "$GITLEAKS_CFG" ]]; then
  if grep -qE '^\s*useDefault\s*=\s*true' "$GITLEAKS_CFG" 2> /dev/null; then
    check_item "gitleaks config" "true" "extends defaults"
  else
    check_item "gitleaks config" "false" "exists but does not extend defaults"
  fi
else
  check_item "gitleaks config" "false" "not found"
fi

# Summary
printf '\n'
if [[ "$STATUS_OK" == "true" ]]; then
  printf '%bCaulking is installed and operational.%b\n\n' "$GREEN" "$RESET"
  printf 'Run %bmake verify%b for full functional tests.\n\n' "$BOLD" "$RESET"
  exit 0
else
  printf '%bCaulking has issues. Run make install to fix.%b\n\n' "$RED" "$RESET"
  exit 1
fi
