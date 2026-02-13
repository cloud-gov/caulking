#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/lib.sh"

on_err_trap
enable_xtrace_if_debug

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
HOOK_DIR="$XDG_CONFIG_HOME/git/hooks"

STATE_DIR="$XDG_CONFIG_HOME/caulking"
PREV_HOOKSPATH_FILE="$STATE_DIR/previous_hookspath"

need_cmd git

info "Removing installed hooks from: $HOOK_DIR"
rm -f "$HOOK_DIR/pre-commit" "$HOOK_DIR/pre-push" "$HOOK_DIR/commit-msg" || true

if [[ -f "$PREV_HOOKSPATH_FILE" ]]; then
  prev="$(cat "$PREV_HOOKSPATH_FILE" || true)"
  if [[ -n "$prev" ]]; then
    info "Restoring previous core.hooksPath: $prev"
    git config --global core.hooksPath "$prev"
  else
    info "Previous core.hooksPath was empty; unsetting"
    git config --global --unset core.hooksPath || true
  fi
else
  info "No previous core.hooksPath recorded; unsetting"
  git config --global --unset core.hooksPath || true
fi

info "Uninstall complete."
info "Note: global gitleaks config is left in place."
