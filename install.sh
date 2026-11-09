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
NO_INSTALL=0

# Quote literal paths for generated POSIX shell launchers, never as executable data.
shell_quote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

runtime_command() {
  local path="$1" prefix rest formula
  [[ "$path" == /* && -x "$path" && ! -d "$path" ]] || die "Required executable must have an absolute path: $path"
  if [[ "$path" == */Cellar/* ]]; then
    prefix="${path%%/Cellar/*}"
    rest="${path#*/Cellar/}"
    formula="${rest%%/*}"
    rest="${rest#*/}"
    rest="${rest#*/}"
    path="$prefix/opt/$formula/$rest"
    [[ -x "$path" ]] || die "Missing stable Homebrew executable: $path"
  fi
  printf '%s\n' "$path"
}

select_runtime() {
  unset RUNTIME_CLI
  if [[ -f "$ROOT_DIR/scripts/package-runtime.sh" ]]; then
    # Only the installed application supplies this generated, fixed baseline.
    # shellcheck source=/dev/null
    source "$ROOT_DIR/scripts/package-runtime.sh"
  else
    RUNTIME_BASH="$(runtime_command "$BASH")"
    RUNTIME_GIT="$(runtime_command "$(command -v git)")"
    RUNTIME_GITLEAKS="$(runtime_command "$(command -v gitleaks)")"
    if have prek; then
      RUNTIME_RUNNER="$(runtime_command "$(command -v prek)")"
    elif have pre-commit; then
      RUNTIME_RUNNER="$(runtime_command "$(command -v pre-commit)")"
    else
      die "Missing required hook runner: prek or pre-commit"
    fi
    RUNTIME_PATH="${RUNTIME_BASH%/*}:${RUNTIME_GIT%/*}:${RUNTIME_GITLEAKS%/*}:${RUNTIME_RUNNER%/*}"
  fi
  # Packages bind the opt application path; source setup binds this checkout.
  RUNTIME_CLI="${RUNTIME_CLI:-$ROOT_DIR/caulking.sh}"
  [[ "$RUNTIME_CLI" == /* && -f "$RUNTIME_CLI" && -r "$RUNTIME_CLI" ]] || die "Missing absolute toolchain CLI: $RUNTIME_CLI"
  [[ -f "${RUNTIME_CLI%/*}/scripts/toolchain.sh" && -r "${RUNTIME_CLI%/*}/scripts/toolchain.sh" ]] || die "Missing readable toolchain helper: ${RUNTIME_CLI%/*}/scripts/toolchain.sh"
  local executable
  for executable in "$RUNTIME_BASH" "$RUNTIME_GIT" "$RUNTIME_GITLEAKS" "$RUNTIME_RUNNER"; do
    runtime_command "$executable" > /dev/null
  done
}

parse_args() {
  case "$#:${1:-}" in
    0:) ;;
    1:--no-install) NO_INSTALL=1 ;;
    *) die "Usage: install.sh [--no-install] (or caulking setup --no-install)" ;;
  esac
}

preflight_setup() {
  ((BASH_VERSINFO[0] >= 4)) || die "setup --no-install requires Bash >=4; run with Homebrew Bash."
  local cmd out version
  for cmd in git gitleaks install mkdir cp grep date chmod; do
    need_cmd "$cmd"
  done
  select_runtime
  "$RUNTIME_BASH" -c '((BASH_VERSINFO[0] >= 4))' || die "Runtime Bash >=4 required"
  "$RUNTIME_GIT" --version > /dev/null 2>&1 || die "git failed to run"
  out="$("$RUNTIME_GITLEAKS" version 2> /dev/null)" || die "gitleaks failed to run"
  if [[ "$out" =~ ^[[:space:]]*(gitleaks[[:space:]]+version[[:space:]]+)?v?([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*$ ]]; then
    version="${BASH_REMATCH[2]}"
  else
    die "Could not parse gitleaks version: $out"
  fi
  version_ge "$version" "8.21.0" || die "gitleaks >=8.21.0 required (found $version)"
  "$RUNTIME_RUNNER" --version > /dev/null 2>&1 || die "${RUNTIME_RUNNER##*/} failed to run"
}

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
    debug "pre-commit present: $(command -v pre-commit)"
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
    if [[ "$NO_INSTALL" -eq 1 ]]; then
      info "Preserving existing global gitleaks config: $GITLEAKS_CFG"
      return 0
    fi
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
  if [[ "$NO_INSTALL" -eq 1 ]]; then
    install -m 0644 "$HOOK_WRAPPER_SRC" "$HOOK_DIR/.caulking-wrapper.sh"
    {
      printf '#!/bin/sh\n# Generated by caulking setup --no-install.\n'
      printf 'unset BASH_ENV ENV\n'
      printf 'PATH=%s:"${PATH:-/usr/bin:/bin}"\nexport PATH\n' "$(shell_quote "$RUNTIME_PATH")"
      printf 'export CAULKING_GIT=%s CAULKING_GITLEAKS=%s CAULKING_RUNNER=%s\n' \
        "$(shell_quote "$RUNTIME_GIT")" "$(shell_quote "$RUNTIME_GITLEAKS")" "$(shell_quote "$RUNTIME_RUNNER")"
      printf 'export CAULKING_BASH=%s CAULKING_TOOLCHAIN_CLI=%s\n' \
        "$(shell_quote "$RUNTIME_BASH")" "$(shell_quote "$RUNTIME_CLI")"
      printf 'exec %s %s --caulking-stage %s "$@"\n' \
        "$(shell_quote "$RUNTIME_BASH")" "$(shell_quote "$HOOK_DIR/.caulking-wrapper.sh")" "$(shell_quote "$stage")"
    } > "$dst"
    chmod 0755 "$dst"
  else
    install -m 0755 "$HOOK_WRAPPER_SRC" "$dst"
  fi
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
  if [[ "$NO_INSTALL" -eq 0 ]]; then
    git config --global --unset hooks.gitleaks > /dev/null 2>&1 || true
  fi
}

main() {
  parse_args "$@"
  need_cmd bash
  need_cmd git
  [[ -f "$HOOK_WRAPPER_SRC" && -r "$HOOK_WRAPPER_SRC" ]] || die "Missing readable hook wrapper source: $HOOK_WRAPPER_SRC"

  if [[ "$NO_INSTALL" -eq 1 ]]; then
    preflight_setup
  else
    install_gitleaks_if_missing
    if ! have prek && ! have pre-commit; then
      install_prek_if_missing
      have prek || install_precommit_if_missing
    fi
  fi
  write_global_gitleaks_config

  store_previous_hookspath_if_needed

  if [[ "$NO_INSTALL" -eq 0 ]]; then
    cleanup_legacy_hooks
  fi
  write_hook pre-commit
  write_hook pre-push

  configure_git_hookspath

  printf '\n'
  info "Done."
  if [[ "$NO_INSTALL" -eq 1 ]]; then
    info "Global hooks use pinned Bash, Git, gitleaks, and runner executables."
    info "Existing gitleaks policy is preserved; setup does not validate or enable default rules in a custom config."
  else
    info "Next: run ./verify.sh"
  fi
}

main "$@"
