#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/lib.sh"

on_err_trap
enable_xtrace_if_debug

# Load standard XDG paths
eval "$(caulking_export_paths)"

HOOK_WRAPPER_SRC="$ROOT_DIR/hooks/hook-wrapper.sh"

install_gitleaks_if_missing() {
  if have gitleaks; then
    debug "gitleaks present: $(command -v gitleaks)"
    return 0
  fi
  if have brew; then
    info "Installing gitleaks via Homebrew..."
    if ! brew install gitleaks 2>&1; then
      warn "Homebrew install encountered issues; checking if gitleaks exists anyway"
    fi
  fi
  have gitleaks || die "gitleaks not found. Install it (gitleaks v8+) and re-run."
}

write_global_gitleaks_config() {
  mkdir -p "$GITLEAKS_DIR"

  if [[ -f "$GITLEAKS_CFG" ]]; then
    if grep -qE '^\[extend\]' "$GITLEAKS_CFG" && grep -qE '^\s*useDefault\s*=\s*true\s*$' "$GITLEAKS_CFG"; then
      info "Global gitleaks config exists and extends defaults: $GITLEAKS_CFG"
      return 0
    fi

    local backup
    backup="$GITLEAKS_CFG.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "$GITLEAKS_CFG" "$backup"
    warn "Upgrading global gitleaks config to extend defaults (backup: $backup)"
  else
    info "Creating global gitleaks config: $GITLEAKS_CFG"
  fi

  cat > "$GITLEAKS_CFG" << 'EOF'
title = "Global Developer Default (gitleaks)"

[extend]
useDefault = true

[allowlist]
description = "Global allowlist for known-safe patterns (keep small)."

regexes = [
  "(?i)example(_|-)?key",
  "(?i)dummy(_|-)?secret",
  "(?i)not(_|-)?a(_|-)?real(_|-)?key",
]

paths = []
EOF
}

store_previous_hookspath_if_needed() {
  mkdir -p "$STATE_DIR"

  local current
  current="$(git config --global --get core.hooksPath || true)"

  # Only store if it's set and it's not already our intended path
  if [[ -n "$current" && "$current" != "$HOOK_DIR" ]]; then
    info "Saving previous core.hooksPath: $current"
    printf '%s\n' "$current" > "$PREV_HOOKSPATH_FILE"
  else
    debug "No previous core.hooksPath to store (current='$current')"
  fi
}

write_hook() {
  local stage="$1"
  local dst="$HOOK_DIR/$stage"

  mkdir -p "$HOOK_DIR"
  install -m 0755 "$HOOK_WRAPPER_SRC" "$dst"
  info "Installed hook: $dst"
}

cleanup_legacy_hooks() {
  # If older versions used commit-msg or other stages, remove to avoid confusion.
  rm -f "$HOOK_DIR/commit-msg" || true
}

configure_git_hookspath() {
  git config --global core.hooksPath "$HOOK_DIR"
  info "Configured: git config --global core.hooksPath $HOOK_DIR"

  # Treat hooks.gitleaks as legacy; ensure it's not set globally.
  git config --global --unset hooks.gitleaks > /dev/null 2>&1 || true
}

main() {
  need_cmd bash
  need_cmd git
  [[ -f "$HOOK_WRAPPER_SRC" ]] || die "Missing hook wrapper source: $HOOK_WRAPPER_SRC"

  chmod +x "$HOOK_WRAPPER_SRC" || true

  install_gitleaks_if_missing
  write_global_gitleaks_config

  store_previous_hookspath_if_needed

  cleanup_legacy_hooks
  write_hook pre-commit
  write_hook pre-push

  configure_git_hookspath

  printf '\n'
  info "Done."
  info "Next: run ./verify.sh"
}

main "$@"
