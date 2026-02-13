#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

say() { printf "%s\n" "$*"; }
die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 2
}

git rev-parse --is-inside-work-tree > /dev/null 2>&1 || die "not in a git repo"

REWRITE_TRACKED=0
FIX_EXEC=1
PRUNE_UNTRACKED=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rewrite-tracked) REWRITE_TRACKED=1 ;;
    --no-exec) FIX_EXEC=0 ;;
    --no-prune) PRUNE_UNTRACKED=0 ;;
    -h | --help)
      cat << 'EOF'
Usage: scripts/cleanup-repo.sh [--rewrite-tracked] [--no-exec] [--no-prune]

Default behavior (SAFE):
- Removes common cruft ONLY if it is UNTRACKED
- Ensures executable bits on known scripts

Dangerous option:
--rewrite-tracked
  - Normalizes CRLF->LF for TRACKED text files (can cause massive diffs)
EOF
      exit 0
      ;;
    *) die "unknown arg: $1" ;;
  esac
  shift
done

say "== Repo cleanup (safe) =="
say "Root: $ROOT"

existing_changes="$(git status --porcelain | wc -l | tr -d ' ')"
if [[ "$existing_changes" -gt 50 ]]; then
  die "refusing to run: repo already has $existing_changes changes. Reset/clean first."
fi

if [[ "$PRUNE_UNTRACKED" -eq 1 ]]; then
  say ""
  say "== Pruning common cruft (UNTRACKED only) =="

  git ls-files --others --exclude-standard -z | while IFS= read -r -d '' f; do
    case "$f" in
      *.swp | *.swo | *.tmp | *.bak) ;;
      .DS_Store | **/.DS_Store) ;;
      ._* | **/._*) ;;
      **/__pycache__/** | **/__pycache__) ;;
      *) continue ;;
    esac
    say "delete: $f"
    rm -rf -- "$f" || true
  done
fi

if [[ "$FIX_EXEC" -eq 1 ]]; then
  say ""
  say "== Ensuring executable bits on scripts =="

  files=(
    "install.sh"
    "uninstall.sh"
    "verify.sh"
    "check_repos.sh"
    "hooks/hook-wrapper.sh"
    "scripts/ensure-tools.sh"
    "scripts/cleanup-repo.sh"
    "scripts/repo-doctor.sh"
  )

  for f in "${files[@]}"; do
    if [[ -f "$f" ]]; then
      chmod +x "$f"
      say "chmod +x $f"
    fi
  done
fi

if [[ "$REWRITE_TRACKED" -eq 1 ]]; then
  say ""
  say "== Normalizing CRLF -> LF for TRACKED files (explicit) =="

  command -v perl > /dev/null 2>&1 || die "perl not found; cannot rewrite tracked files safely"

  git ls-files -z | while IFS= read -r -d '' f; do
    perl -pi -e 's/\r\n/\n/g' "$f" 2> /dev/null || true
  done
fi

say ""
say "== Summary =="
git status --porcelain || true
say ""
say "Done."
