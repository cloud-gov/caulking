#!/usr/bin/env bash
set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
HOOK_DIR="$XDG_CONFIG_HOME/git/hooks"

STATE_DIR="$XDG_CONFIG_HOME/caulking"
PREV_HOOKSPATH_FILE="$STATE_DIR/previous_hookspath"

say() { printf "%s\n" "$*"; }

say "Removing installed hooks from: $HOOK_DIR"
rm -f "$HOOK_DIR/pre-commit" "$HOOK_DIR/pre-push" "$HOOK_DIR/commit-msg" || true

if [[ -f "$PREV_HOOKSPATH_FILE" ]]; then
  prev="$(cat "$PREV_HOOKSPATH_FILE")"
  if [[ -n "$prev" ]]; then
    say "Restoring previous core.hooksPath: $prev"
    git config --global core.hooksPath "$prev"
  else
    say "Previous core.hooksPath was empty; unsetting"
    git config --global --unset core.hooksPath || true
  fi
else
  say "No previous core.hooksPath recorded; unsetting"
  git config --global --unset core.hooksPath || true
fi

say "Uninstall complete."
say "Note: global gitleaks config is left in place."
