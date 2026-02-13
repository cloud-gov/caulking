#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib.sh"

on_err_trap
enable_xtrace_if_debug

need_cmd git
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || die "not in a git repo"

root="$(git rev-parse --show-toplevel)"
cd "$root"

info "== Repo Doctor =="
info "Root: $root"

changes="$(git status --porcelain | wc -l | tr -d ' ')"
info "Working tree changes: $changes"

if [[ "$changes" -gt 0 ]]; then
  printf '\n'
  info "Top changes:"
  git status --porcelain | head -n 25
fi

printf '\n'
info "Untracked files (first 25):"
git ls-files --others --exclude-standard | head -n 25 || true

printf '\n'
info "If you see massive unexpected changes:"
info "  git reset --hard HEAD"
info "  git clean -fd"
