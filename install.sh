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

install_prek_if_missing() {
  if have prek; then
    debug "prek present: $(command -v prek)"
    return 0
  fi
  if have brew; then
    info "Installing prek via Homebrew..."
    if ! brew install prek 2>&1; then
      warn "Homebrew install encountered issues; checking if prek exists anyway"
    fi
  fi
  if have prek; then
    info "prek installed successfully"
    return 0
  fi
  warn "prek not found. Install it for pre-commit hook support."
  return 0
}

install_precommit_if_missing() {
  if have pre-commit; then
    local existing_path
    existing_path="$(command -v pre-commit)"
    debug "pre-commit present: $existing_path"

    # Check if it's from mise/other non-brew sources
    if [[ "$existing_path" != *"/opt/homebrew"* && "$existing_path" != *"/usr/local"* ]]; then
      if have brew; then
        info "pre-commit found at $existing_path (non-Homebrew)"
        info "Uninstalling from pip/pipx and installing via Homebrew for consistency..."

        # Try to uninstall from pip/pipx
        if have pip; then
          pip uninstall -y pre-commit 2>&1 || true
        fi
        if have pipx; then
          pipx uninstall pre-commit 2>&1 || true
        fi

        # Install via Homebrew
        if brew install pre-commit 2>&1; then
          info "pre-commit installed via Homebrew"
          return 0
        else
          warn "Homebrew install encountered issues; checking if pre-commit exists anyway"
        fi
      fi
    fi
    return 0
  fi

  if have brew; then
    info "Installing pre-commit via Homebrew..."
    if ! brew install pre-commit 2>&1; then
      warn "Homebrew install encountered issues; checking if pre-commit exists anyway"
    fi
  fi

  if have pre-commit; then
    info "pre-commit installed successfully"
    return 0
  fi
  warn "pre-commit not found. Install it for pre-commit hook support."
  return 0
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

# AWS ARN detection - warns on hardcoded 12-digit account IDs
# Detects: arn:aws:iam::123456789012:user/admin
# Allows: arn:aws:iam::${ACCOUNT_ID}:user/admin (variable interpolation)
# Allows: arn:aws:s3:::bucket-name (S3 buckets have no account ID field)
# See: https://github.com/cloud-gov/caulking/issues/111
[[rules]]
id = "aws-arn-account-id"
description = "AWS ARN with hardcoded account ID (reconnaissance risk)"
regex = '''arn:aws(-us-gov|-cn)?:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:[a-zA-Z0-9/_=+.@:-]+'''
keywords = ["arn:aws"]
tags = ["aws", "arn", "account-id"]

  [rules.allowlist]
  description = "Safe ARN patterns (variable interpolation, documentation)"
  regexes = [
    # Variable interpolation patterns
    '''\$\{[^}]*ACCOUNT[^}]*\}''',
    '''\$\{[^}]*AWS[^}]*\}''',
    '''\$ACCOUNT''',
    '''\$AWS_ACCOUNT''',
    # Documentation example account IDs (AWS docs use these)
    '''123456789012''',
    '''111122223333''',
    '''444455556666''',
    '''999999999999''',
    # Wildcard patterns
    ''':\*:''',
  ]

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
  install_prek_if_missing
  install_precommit_if_missing
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
