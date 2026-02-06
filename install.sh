#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
HOOK_DIR="$XDG_CONFIG_HOME/git/hooks"
GITLEAKS_DIR="$XDG_CONFIG_HOME/gitleaks"
GITLEAKS_CFG="$GITLEAKS_DIR/config.toml"

HOOK_WRAPPER_SRC="$ROOT_DIR/hooks/hook-wrapper.sh"

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

install_gitleaks() {
  if have_cmd gitleaks; then return 0; fi
  if have_cmd brew; then
    say "Installing gitleaks via Homebrew..."
    brew install gitleaks
    return 0
  fi
  die "gitleaks not found. Install it and re-run install.sh"
}

install_prek() {
  # prek is optional; install if possible but do not hard fail.
  if have_cmd prek; then return 0; fi
  if have_cmd uv; then
    say "Installing prek via uv tool..."
    uv tool install prek
    return 0
  fi
  if have_cmd brew; then
    say "Installing prek via Homebrew..."
    brew install prek >/dev/null 2>&1 || true
    return 0
  fi
  say "NOTE: prek not installed (optional). Repo-level hooks via .pre-commit-config.yaml will be skipped."
  return 0
}

write_global_gitleaks_config() {
  mkdir -p "$GITLEAKS_DIR"

  # If file exists but DOES NOT extend defaults, upgrade it.
  if [[ -f "$GITLEAKS_CFG" ]]; then
    if ! grep -qE '^\[extend\]' "$GITLEAKS_CFG" || ! grep -qE '^\s*useDefault\s*=\s*true\s*$' "$GITLEAKS_CFG"; then
      # shellcheck disable=SC2155
      local backup="$GITLEAKS_CFG.bak.$(date +%Y%m%d%H%M%S)"
      cp -a "$GITLEAKS_CFG" "$backup"
      say "Upgrading global gitleaks config to extend defaults (backup: $backup)"
    else
      say "Global gitleaks config exists and extends defaults: $GITLEAKS_CFG"
      return 0
    fi
  else
    say "Creating global gitleaks config: $GITLEAKS_CFG"
  fi

  cat >"$GITLEAKS_CFG" <<'EOF'
title = "Global Developer Default (gitleaks)"

# Critical: keep default detectors enabled.
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

write_hook() {
  local stage="$1"         # pre-commit, pre-push
  local dst="$HOOK_DIR/$stage"

  mkdir -p "$HOOK_DIR"
  install -m 0755 "$HOOK_WRAPPER_SRC" "$dst"
  say "Installed hook: $dst"
}

cleanup_legacy_hooks() {
  # Remove a legacy hook that breaks commits if present.
  if [[ -e "$HOOK_DIR/commit-msg" ]]; then
    rm -f "$HOOK_DIR/commit-msg"
    say "Removed legacy hook: $HOOK_DIR/commit-msg"
  fi
}

configure_git_hookspath() {
  need_cmd git
  git config --global core.hooksPath "$HOOK_DIR"
  say "Configured: git config --global core.hooksPath $HOOK_DIR"
  # Keep legacy behavior if you still use it elsewhere.
  git config --global hooks.gitleaks true
}

main() {
  need_cmd bash
  need_cmd git
  [[ -f "$HOOK_WRAPPER_SRC" ]] || die "Missing hook wrapper source: $HOOK_WRAPPER_SRC"

  chmod +x "$HOOK_WRAPPER_SRC" || true

  install_gitleaks
  install_prek

  write_global_gitleaks_config

  cleanup_legacy_hooks
  write_hook pre-commit
  write_hook pre-push

  configure_git_hookspath

  say ""
  say "Done."
  say "Next: run ./verify.sh"
}

main "$@"
