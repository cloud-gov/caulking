#!/usr/bin/env bash
# Caulking uninstaller — removes user shim, optional hooksPath, and (PURGE=1) PATH block.
# Idempotent. Loud. Safe.
#
# Env:
#   PURGE=1   Also remove the PATH block we added between our markers in rc files.

set -euo pipefail

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
CAULKING_HOME="${CAULKING_HOME:-$XDG_DATA_HOME/caulking}"
HOOKS_DIR="${HOOKS_DIR:-$HOME/.githooks}"

say()  { printf '%s\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }

mark_begin="# >>> caulking PATH >>>"
mark_end="# <<< caulking PATH <<<"

RC_FILES=(
  "$HOME/.zshrc"
  "$HOME/.bashrc"
  "$HOME/.bash_profile"
  "$HOME/.profile"
)

backup_file() {
  local f="$1"
  [[ -e "$f" || -L "$f" ]] || return 0
  local ts; ts="$(date +%Y%m%d-%H%M%S)"
  local dest="${f}.bak.${ts}"
  cp -a "$f" "$dest"
  say "[caulking] Backed up: $f -> $dest"
}

remove_path_block() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  if grep -qF "$mark_begin" "$f"; then
    backup_file "$f"
    # Portable sed (BSD/GNU): remove from marker begin to end inclusive
    awk -v mb="$mark_begin" -v me="$mark_end" '
      BEGIN {skip=0}
      index($0, mb) {skip=1; next}
      index($0, me) {skip=0; next}
      skip==0 {print}
    ' "$f" > "${f}.tmp"
    mv "${f}.tmp" "$f"
    say "[caulking] Removed PATH block from $(basename "$f")"
  fi
}

say "[caulking] removing user shim"
rm -f "$XDG_BIN_HOME/caulking" || true

if git config --global --get core.hooksPath >/dev/null 2>&1; then
  if [ "$(git config --global --get core.hooksPath)" = "$HOOKS_DIR" ]; then
    say "[caulking] unsetting git core.hooksPath"
    git config --global --unset core.hooksPath || true
  fi
fi

say "[caulking] removing hooks dir files (kept if not empty)"
rm -f "$HOOKS_DIR/pre-commit" || true
rmdir "$HOOKS_DIR" 2>/dev/null || true

if [ "${PURGE:-0}" = "1" ]; then
  say "[caulking] PURGE=1 — removing PATH blocks from rc files"
  for rc in "${RC_FILES[@]}"; do
    remove_path_block "$rc"
  done
  say "[caulking] PURGE=1 — removing $CAULKING_HOME"
  rm -rf "$CAULKING_HOME"
fi

say "[caulking] uninstall complete."
