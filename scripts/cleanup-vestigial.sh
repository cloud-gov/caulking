#!/usr/bin/env bash
set -euo pipefail

# scripts/cleanup-vestigial.sh
#
# Purpose:
# - Remove vestigial/legacy repo content and common dev cruft
# - Normalize executability for scripts
# - Keep behavior SAFE by default: only delete UNTRACKED files
# - Optionally remove legacy tracked files *only* when explicitly asked
#
# Usage:
#   ./scripts/cleanup-vestigial.sh
#   ./scripts/cleanup-vestigial.sh --apply
#   ./scripts/cleanup-vestigial.sh --apply --remove-legacy-tracked
#
# Flags:
#   --apply                 Actually delete files / apply changes. Otherwise dry-run.
#   --remove-legacy-tracked Remove legacy tracked files (pre-commit.sh etc). Dangerous.
#   --aggressive-untracked  Also remove more untracked junk patterns.
#   -h|--help               Show help.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 2; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not in a git repo"

APPLY=0
REMOVE_LEGACY_TRACKED=0
AGGRESSIVE_UNTRACKED=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --remove-legacy-tracked) REMOVE_LEGACY_TRACKED=1 ;;
    --aggressive-untracked) AGGRESSIVE_UNTRACKED=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: scripts/cleanup-vestigial.sh [options]

Options:
  --apply                  Actually apply deletions/changes (default: dry-run)
  --remove-legacy-tracked  Remove legacy tracked files (dangerous; makes diffs)
  --aggressive-untracked   Remove additional untracked junk patterns
  -h, --help               Show help

Notes:
- Default is DRY-RUN.
- This script never rewrites tracked files' content.
- It can remove certain tracked files ONLY with --remove-legacy-tracked.
EOF
      exit 0
      ;;
    *) die "unknown arg: $1" ;;
  esac
  shift
done

say "== Cleanup vestigial content =="
say "Root: $ROOT"
say "Mode: $([[ "$APPLY" -eq 1 ]] && echo APPLY || echo DRY-RUN)"

# Bail out if repo is already messy — you don't want “cleanup” buried in unrelated diffs.
changes="$(git status --porcelain | wc -l | tr -d ' ')"
if [[ "$changes" -gt 80 ]]; then
  die "refusing: repo already has $changes changes. Commit/stash/reset first."
fi

run() {
  if [[ "$APPLY" -eq 1 ]]; then
    "$@"
  else
    printf "DRY: %q" "$1"
    shift
    for a in "$@"; do printf " %q" "$a"; done
    printf "\n"
  fi
}

# -------------------------------------------------------------------
# 1) UNTRACKED CRUFT REMOVAL (SAFE)
# -------------------------------------------------------------------
say ""
say "== Prune untracked cruft (safe) =="

untracked_list="$(git ls-files --others --exclude-standard -z || true)"
if [[ -n "$untracked_list" ]]; then
  while IFS= read -r -d '' f; do
    case "$f" in
      .DS_Store|**/.DS_Store|._*|**/._*|*.swp|*.swo|*.tmp|*.bak) ;;
      .idea/**|.vscode/**|.pytest_cache/**|**/__pycache__/**) ;;
      .coverage|coverage/**|dist/**|build/**|node_modules/**) ;;
      .terraform/**|.terragrunt-cache/**|.cache/**) ;;
      *.log) ;;
      *) continue ;;
    esac

    # Only delete if truly untracked.
    say "delete (untracked): $f"
    run rm -rf -- "$f"
  done <<<"$untracked_list"
else
  say "No untracked files."
fi

if [[ "$AGGRESSIVE_UNTRACKED" -eq 1 ]]; then
  say ""
  say "== Aggressive untracked prune =="
  # Things that are commonly generated locally but sometimes appear during dev.
  patterns=(
    "repomix-output.*"
    "*.nessus"
    "*.zip"
    "*.tar"
    "*.tar.gz"
  )
  for p in "${patterns[@]}"; do
    # only remove if untracked
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
        continue
      fi
      say "delete (untracked aggressive): $f"
      run rm -rf -- "$f"
    done < <(find "$ROOT" -maxdepth 2 -name "$p" -print 2>/dev/null || true)
  done
fi

# -------------------------------------------------------------------
# 2) ENSURE EXECUTABLE BITS FOR SCRIPTS
# -------------------------------------------------------------------
say ""
say "== Ensure executable bits =="

exec_files=(
  "install.sh"
  "uninstall.sh"
  "verify.sh"
  "check_repos.sh"
  "hooks/hook-wrapper.sh"
  "scripts/ensure-tools.sh"
  "scripts/repo-doctor.sh"
  "scripts/cleanup-repo.sh"
  "scripts/cleanup-vestigial.sh"
)

for f in "${exec_files[@]}"; do
  if [[ -f "$f" ]]; then
    say "chmod +x $f"
    run chmod +x "$f"
  fi
done

# -------------------------------------------------------------------
# 3) OPTIONAL: REMOVE LEGACY TRACKED FILES
# -------------------------------------------------------------------
# These are “vestigial” given the new architecture (global hook wrapper in hooks/).
# Keeping them isn't harmful, but they confuse readers and can diverge.
#
if [[ "$REMOVE_LEGACY_TRACKED" -eq 1 ]]; then
  say ""
  say "== Remove legacy tracked files (dangerous) =="
  say "This will modify the repo and produce diffs."

  legacy_tracked=(
    # Legacy per-repo hook logic (interactive; doesn't belong in a global hook path)
    "pre-commit.sh"
  )

  for f in "${legacy_tracked[@]}"; do
    if [[ -f "$f" ]]; then
      say "remove tracked: $f"
      run git rm -f "$f"
    fi
  done
fi

say ""
say "== Summary =="
git status --porcelain || true
say ""
say "Done."
say ""
say "Tip: if you want this to actually change the repo, re-run with --apply"
