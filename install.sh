#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
HOOK_DIR="$XDG_CONFIG_HOME/git/hooks"
GITLEAKS_DIR="$XDG_CONFIG_HOME/gitleaks"
GITLEAKS_CFG="$GITLEAKS_DIR/config.toml"

STATE_DIR="$XDG_CONFIG_HOME/caulking"
PREV_HOOKSPATH_FILE="$STATE_DIR/previous_hookspath"

HOOK_WRAPPER_SRC="$ROOT_DIR/hooks/hook-wrapper.sh"

say() { printf "%s\n" "$*"; }
die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

need_cmd() { command -v "$1" > /dev/null 2>&1 || die "Missing required command: $1"; }
have_cmd() { command -v "$1" > /dev/null 2>&1; }

install_gitleaks() {
  if have_cmd gitleaks; then
    return 0
  fi
  if have_cmd brew; then
    say "Installing gitleaks via Homebrew..."
    brew install gitleaks > /dev/null 2>&1 || true
    return 0
  fi
  die "gitleaks not found. Install it and re-run install.sh"
}

write_global_gitleaks_config() {
  mkdir -p "$GITLEAKS_DIR"

  if [[ -f "$GITLEAKS_CFG" ]]; then
    if grep -qE '^\[extend\]' "$GITLEAKS_CFG" && grep -qE '^\s*useDefault\s*=\s*true\s*$' "$GITLEAKS_CFG"; then
      say "Global gitleaks config exists and extends defaults: $GITLEAKS_CFG"
      return 0
    fi

    local backup
    backup="$GITLEAKS_CFG.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "$GITLEAKS_CFG" "$backup"
    say "Upgrading global gitleaks config to extend defaults (backup: $backup)"
  else
    say "Creating global gitleaks config: $GITLEAKS_CFG"
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

  if [[ -n "$current" && "$current" != "$HOOK_DIR" ]]; then
    say "Saving previous core.hooksPath: $current"
    printf '%s\n' "$current" > "$PREV_HOOKSPATH_FILE"
  fi
}

write_hook() {
  local stage="$1"
  local dst="$HOOK_DIR/$stage"

  mkdir -p "$HOOK_DIR"
  install -m 0755 "$HOOK_WRAPPER_SRC" "$dst"
  say "Installed hook: $dst"
}

cleanup_legacy_hooks() {
  rm -f "$HOOK_DIR/commit-msg" || true
}

configure_git_hookspath() {
  need_cmd git
  git config --global core.hooksPath "$HOOK_DIR"
  say "Configured: git config --global core.hooksPath $HOOK_DIR"

  git config --global --unset hooks.gitleaks > /dev/null 2>&1 || true
}

main() {
  need_cmd bash
  need_cmd git
  [[ -f "$HOOK_WRAPPER_SRC" ]] || die "Missing hook wrapper source: $HOOK_WRAPPER_SRC"

  chmod +x "$HOOK_WRAPPER_SRC" || true

  install_gitleaks
  write_global_gitleaks_config

  store_previous_hookspath_if_needed

  cleanup_legacy_hooks
  write_hook pre-commit
  write_hook pre-push

  configure_git_hookspath

  say ""
  say "Done."
  say "Next: run ./verify.sh"
}

main "$@"
