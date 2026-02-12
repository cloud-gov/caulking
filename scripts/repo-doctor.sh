#!/usr/bin/env bash
set -euo pipefail

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 2; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not in a git repo"
root="$(git rev-parse --show-toplevel)"
cd "$root"

say "== Repo Doctor =="
say "Root: $root"

changes="$(git status --porcelain | wc -l | tr -d ' ')"
say "Working tree changes: $changes"

if [[ "$changes" -gt 0 ]]; then
  say ""
  say "Top changes:"
  git status --porcelain | head -n 25
fi

say ""
say "Untracked files (first 25):"
git ls-files --others --exclude-standard | head -n 25 || true

say ""
say "If you see massive unexpected changes:"
say "  git reset --hard HEAD"
say "  git clean -fd"
