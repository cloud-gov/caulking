#!/usr/bin/env bash
# trailing-whitespace.sh - Trim trailing whitespace from files
#
# Usage: trailing-whitespace.sh FILE [FILE...]
#
# Portable across macOS (BSD sed) and Linux (GNU sed): `sed -i` takes an
# incompatible in-place suffix argument between the two, so instead of `sed -i`
# we write to a mktemp file and atomically move it back (same approach as
# end-of-file-fixer.sh). No GNU-only flags.
#
# pre-commit "fixer" contract: if we modify any file we EXIT NON-ZERO so the
# commit is blocked and the developer re-stages the fixed content (otherwise the
# commit would proceed with the un-fixed staged blob). We also preserve the
# original file mode across the atomic replace (mktemp defaults to 0600, which
# would otherwise strip +x / group bits).
#
# Exit codes:
#   0 - nothing needed fixing (or only skipped files)
#   1 - at least one file was fixed (re-stage and commit again)
#   2 - at least one file could not be processed; NO file was modified
#       partially. Originals are always left byte-identical on failure.
#
# DATA-LOSS HISTORY (do not reintroduce): this script used to run the rewrite in
# a subshell that was the left-hand side of a pipeline (`( ... ) | grep -q`) so
# the parent could learn "changed" from stdout. Bash suspends `set -e` inside a
# pipeline used as an `if` condition, so a failing `sed` was never noticed and
# its partial/empty output was `mv`d over the original. BSD sed SIGABRTs on NUL
# bytes, which destroyed such files outright; any other sed failure truncated
# them. Two rules follow, and both are load-bearing:
#   1. Never signal status through stdout markers, because that forces the
#      pipeline that disables `set -e`. Use a return code / global instead.
#   2. Never rely on `set -e` for the write path. Every command that can fail is
#      checked explicitly, so correctness does not depend on which syntactic
#      context the code happens to sit in.

set -euo pipefail

# Result of the last fix_file() call: unchanged | changed | skipped | error.
# fix_file() always returns 0 and reports through this variable, so it is never
# invoked in a condition context (which is what suspends `set -e`).
FIX_RESULT=""

# Temp file owned by the in-progress fix_file() call, for the cleanup trap.
TMPFILE=""

cleanup() {
  if [ -n "$TMPFILE" ]; then
    rm -f "$TMPFILE"
    TMPFILE=""
  fi
  return 0
}
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Print the octal permission bits of "$1" portably (GNU stat vs BSD stat).
file_mode() {
  stat -c '%a' "$1" 2> /dev/null || stat -f '%Lp' "$1" 2> /dev/null || true
}

tab="$(printf '\t')"
ws="[ ${tab}]"

# has_nul FILE
#   0 - file contains at least one NUL byte
#   1 - file contains no NUL byte
#   2 - could not determine (treat as an error, never as "safe")
has_nul() {
  local f="$1" size stripped rc=0
  size="$(LC_ALL=C wc -c < "$f")" || return 2
  stripped="$(LC_ALL=C tr -d '\000' < "$f" | LC_ALL=C wc -c)" || rc=$?
  [ "$rc" -eq 0 ] || return 2
  [ "$size" -eq "$stripped" ] || return 0
  return 1
}

# counts FILE -> prints "<newlines> <bytes>"
counts() {
  LC_ALL=C wc -lc < "$1"
}

# content_digest FILE -> checksum of FILE with all spaces, tabs and newlines
# deleted. The substitution only ever deletes spaces/tabs, so this digest is
# invariant across a faithful rewrite: any difference means non-whitespace
# content was lost or altered. This is what catches a truncation the line/byte
# invariants cannot see, e.g. "aaaa   \n" (1 line, 8 bytes) rewritten as "a\n"
# (1 line, 2 bytes).
content_digest() {
  LC_ALL=C tr -d " ${tab}\\n" < "$1" | cksum
}

# fix_file FILE - rewrite FILE without trailing spaces/tabs.
# Always returns 0; sets FIX_RESULT. Guarantees FILE is either fully rewritten
# or left byte-identical -- there is no intermediate state.
fix_file() {
  local file="$1"
  local path rc mode in_l in_c out_l out_c in_d out_d
  FIX_RESULT="error"

  # A name starting with "-" would be parsed as an option by mktemp/chmod/etc.
  # BSD sed does not accept "--" as an end-of-options marker, so prefix "./"
  # instead: that works for every tool below. "$file" is still used in
  # messages so the user sees the name they passed.
  case "$file" in
    -*) path="./$file" ;;
    *) path="$file" ;;
  esac

  # Cheap pre-check first: if there is nothing to strip we do no work at all --
  # no temp file, no NUL scan. This keeps the common (and idempotent
  # second-run) path read-only, so a clean file in a read-only directory still
  # succeeds and inode/mtime stay untouched. The pattern is the exact
  # complement of the sed substitution below, so it can never skip a file that
  # sed would have modified. LC_ALL=C so an invalid multibyte sequence cannot
  # make grep fail; grep tolerates NUL bytes (unlike BSD sed) and still
  # reports a match.
  rc=0
  LC_ALL=C grep -q "${ws}${ws}*\$" -- "$path" || rc=$?
  case "$rc" in
    0) ;; # has trailing whitespace, continue
    1)
      FIX_RESULT="unchanged"
      return 0
      ;;
    *)
      printf 'Error: %s: unreadable; left unchanged\n' "$file" >&2
      return 0
      ;;
  esac

  # Binary-ish input: BSD sed aborts on NUL bytes while GNU sed does not, so
  # processing these would both risk data loss and make the same file behave
  # differently per platform. `types: [text]` filters most binaries, but
  # identify() only sniffs the first 1024 bytes, so a later NUL still reaches
  # us. Skip: a whitespace fixer has no business rewriting binary payloads.
  rc=0
  has_nul "$path" || rc=$?
  case "$rc" in
    0)
      printf 'Skipped (contains NUL bytes, not text): %s\n' "$file" >&2
      FIX_RESULT="skipped"
      return 0
      ;;
    1) ;; # no NUL, safe to process
    *)
      printf 'Error: %s: unable to scan for NUL bytes; left unchanged\n' \
        "$file" >&2
      return 0
      ;;
  esac

  # A write is genuinely required from here on, so an unusable temp file is a
  # hard failure (fail CLOSED). The old code exited the subshell 2 here, which
  # the `grep -q` consumer read as "no change" and reported success.
  rc=0
  TMPFILE="$(mktemp "${path}.XXXXXX")" || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$TMPFILE" ]; then
    TMPFILE=""
    printf 'Error: %s: failed to create temp file (directory writable?)\n' \
      "$file" >&2
    return 0
  fi

  # Strip trailing spaces/tabs from every line. Use an explicit space+tab
  # class (not [[:space:]], which can match newlines on some seds) to stay
  # portable and line-scoped.
  rc=0
  sed "s/${ws}*\$//" "$path" > "$TMPFILE" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'Error: %s: sed failed (exit %s); left unchanged\n' \
      "$file" "$rc" >&2
    cleanup
    return 0
  fi

  # Sanity invariants. We only reach here when grep found at least one
  # trailing blank, so a faithful rewrite must: keep every line (a truncated
  # or empty write loses newlines), not grow (the substitution only deletes),
  # and stay non-empty. This catches a sed that exits 0 with partial output, a
  # short write, and a full disk -- none of which set an exit status we could
  # otherwise observe. `out_l` may legitimately exceed `in_l` by one on seds
  # that append a missing final newline; that cannot breach the byte ceiling
  # because at least one blank was removed.
  rc=0
  read -r in_l in_c <<< "$(counts "$path")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'Error: %s: could not measure original; left unchanged\n' \
      "$file" >&2
    cleanup
    return 0
  fi
  rc=0
  read -r out_l out_c <<< "$(counts "$TMPFILE")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'Error: %s: could not measure rewrite; left unchanged\n' \
      "$file" >&2
    cleanup
    return 0
  fi
  if [ "$out_l" -lt "$in_l" ] || [ "$out_l" -gt $((in_l + 1)) ] ||
    [ "$out_c" -gt "$in_c" ]; then
    printf 'Error: %s: rewrite failed sanity check (%s/%s lines, %s/%s bytes); left unchanged\n' \
      "$file" "$out_l" "$in_l" "$out_c" "$in_c" >&2
    cleanup
    return 0
  fi

  # Strongest check: the non-whitespace content must be bit-identical. Catches
  # a truncation that happens to preserve the line count and stay under the
  # byte ceiling, which the counts above cannot see.
  rc=0
  in_d="$(content_digest "$path")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'Error: %s: could not digest original; left unchanged\n' \
      "$file" >&2
    cleanup
    return 0
  fi
  rc=0
  out_d="$(content_digest "$TMPFILE")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'Error: %s: could not digest rewrite; left unchanged\n' \
      "$file" >&2
    cleanup
    return 0
  fi
  if [ "$in_d" != "$out_d" ]; then
    printf 'Error: %s: rewrite altered non-whitespace content; left unchanged\n' \
      "$file" >&2
    cleanup
    return 0
  fi

  rc=0
  cmp -s "$TMPFILE" "$path" || rc=$?
  case "$rc" in
    0)
      # Byte-identical. The grep gate above means we should not get here;
      # kept so that an unexpected no-op can never trigger a needless
      # replace (which would churn the inode and mtime).
      cleanup
      FIX_RESULT="unchanged"
      return 0
      ;;
    1) ;; # differs, install it
    *)
      printf 'Error: %s: cmp failed (exit %s); left unchanged\n' \
        "$file" "$rc" >&2
      cleanup
      return 0
      ;;
  esac

  # Preserve the original mode before replacing (mktemp is 0600). If we cannot
  # determine or apply it, fail closed rather than silently tightening the
  # file's permissions as a side effect of a whitespace fix.
  mode="$(file_mode "$path")"
  if [ -z "$mode" ]; then
    printf 'Error: %s: could not read file mode; left unchanged\n' \
      "$file" >&2
    cleanup
    return 0
  fi
  rc=0
  chmod "$mode" "$TMPFILE" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'Error: %s: could not preserve mode %s; left unchanged\n' \
      "$file" "$mode" >&2
    cleanup
    return 0
  fi

  # rename(2) is atomic: it either fully replaces the file or leaves it alone.
  rc=0
  mv "$TMPFILE" "$path" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'Error: %s: could not replace file; left unchanged\n' \
      "$file" >&2
    cleanup
    return 0
  fi
  TMPFILE=""
  FIX_RESULT="changed"
  return 0
}

changed=0
errors=0

for file in "$@"; do
  # Skip symlinks: we must not replace a symlink with a regular file.
  if [ -f "$file" ] && [ ! -L "$file" ]; then
    fix_file "$file"
    case "$FIX_RESULT" in
      changed)
        printf 'Fixed trailing whitespace: %s\n' "$file" >&2
        changed=1
        ;;
      error)
        errors=1
        ;;
      *) ;; # unchanged / skipped
    esac
  fi
done

# A processing failure outranks a successful fix: exit 2 so the caller can tell
# "re-stage your files" (1) from "something is broken" (2).
if [ "$errors" -ne 0 ]; then
  exit 2
fi

# Non-zero when we changed something, so pre-commit blocks the commit and the
# developer re-stages. Zero when nothing needed fixing.
exit "$changed"
