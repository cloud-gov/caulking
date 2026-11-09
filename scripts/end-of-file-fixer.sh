#!/usr/bin/env bash
# end-of-file-fixer.sh - Ensure files end with exactly one newline
#
# Usage: end-of-file-fixer.sh FILE [FILE...]
#
# Portable across macOS and Linux: `truncate` is not installed on macOS by
# default, so instead of truncating in place we write to a mktemp file and
# atomically move it back (same approach as trailing-whitespace.sh). No GNU-only
# flags.
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
# DATA-LOSS HISTORY (do not reintroduce): this script used to read the whole file
# through `content=$(cat "$file")`. Bash DISCARDS NUL bytes in command
# substitution, so any file containing one was silently rewritten without it --
# measured: 6100620a63 became 61620a630a, same byte count, and the script exited
# 0. The rewrite also ran in a subshell used as `( ... ) || exit 1`, and bash
# suspends `set -e` on the left of `||`, so `cat`'s status was never checked: a
# stub cat printing "PART" and exiting 5 turned a 31-byte file into 5 bytes, rc=0.
# Three rules follow, and all are load-bearing:
#   1. Never read file content into a shell variable. Bytes must flow file-to-file
#      so NULs and invalid multibyte sequences survive.
#   2. Never rely on `set -e` for the write path. Every command that can fail is
#      checked explicitly, so correctness does not depend on which syntactic
#      context the code happens to sit in.
#   3. Never signal status through stdout markers, because that forces a pipeline
#      that disables `set -e`. Use a return code / global instead.

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

# trailing_newline_count FILE -> number of consecutive \n at end of FILE.
# Counted by deleting everything up to the last non-newline byte. Uses `od` so
# NUL bytes and invalid multibyte sequences cannot corrupt the measurement.
trailing_newline_count() {
  LC_ALL=C od -An -v -tu1 < "$1" |
    LC_ALL=C tr -s ' ' '\n' |
    LC_ALL=C awk 'NF { if ($1 == 10) n++; else n = 0 } END { print n + 0 }'
}

# body_digest FILE -> checksum of FILE with every trailing newline removed.
#
# This is the invariant that makes the rewrite safe to install. This hook may
# legitimately add or remove trailing newlines, so (unlike trailing-whitespace.sh)
# byte count and line count are BOTH expected to change and cannot be used as
# bounds. What must never change is everything before the final run of newlines.
# Comparing that digest catches any corruption the counts cannot see: a dropped
# NUL, a truncation, a partial write, or a `cat` that lies about its exit status.
#
# `sed -e :a -e '/^$/{$d;N;ba' -e '}'` is the portable "delete trailing blank
# lines" idiom, but BSD sed aborts on NUL bytes, so it is not usable here. `od`
# is used instead: it is POSIX, byte-exact, and NUL-safe.
body_digest() {
  LC_ALL=C od -An -v -tu1 < "$1" |
    LC_ALL=C tr -s ' ' '\n' |
    LC_ALL=C awk '
            NF {
                if ($1 == 10) { pending++ }
                else {
                    while (pending-- > 0) { printf "10\n" }
                    pending = 0
                    printf "%s\n", $1
                }
            }
        ' | cksum
}

# fix_file FILE - rewrite FILE so it ends with exactly one newline.
# Always returns 0; sets FIX_RESULT. Guarantees FILE is either fully rewritten
# or left byte-identical -- there is no intermediate state.
fix_file() {
  local file="$1"
  local path rc mode nl in_d out_d body_bytes keep
  FIX_RESULT="error"

  # A name starting with "-" would be parsed as an option by mktemp/chmod/etc.
  # Prefix "./" so every tool below treats it as a path. "$file" is still used
  # in messages so the user sees the name they passed.
  case "$file" in
    -*) path="./$file" ;;
    *) path="$file" ;;
  esac

  # Cheap pre-check first: if the file already ends with exactly one newline
  # there is nothing to do, and we do no work at all -- no temp file, no NUL
  # scan. This keeps the common (and idempotent second-run) path read-only, so
  # a clean file in a read-only directory still succeeds and inode/mtime stay
  # untouched. The previous version rewrote unconditionally, churning both.
  rc=0
  nl="$(trailing_newline_count "$path")" || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$nl" ]; then
    printf 'Error: %s: unreadable; left unchanged\n' "$file" >&2
    return 0
  fi
  if [ "$nl" -eq 1 ]; then
    FIX_RESULT="unchanged"
    return 0
  fi

  # Binary-ish input: rewriting a binary payload is not this hook's job, and
  # doing it through shell text tools risks corrupting it. `types: [text]`
  # filters most binaries, but identify() only sniffs the first 1024 bytes, so
  # a later NUL still reaches us. Skip rather than mangle -- this is the exact
  # case the old `content=$(cat)` silently destroyed.
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
  # hard failure (fail CLOSED). The old code exited the subshell 1 here, which
  # `|| exit 1` turned into a whole-run abort on some paths and a silent
  # success on others.
  rc=0
  TMPFILE="$(mktemp "${path}.XXXXXX")" || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$TMPFILE" ]; then
    TMPFILE=""
    printf 'Error: %s: failed to create temp file (directory writable?)\n' \
      "$file" >&2
    return 0
  fi

  # Build the rewrite byte-for-byte: copy everything up to the last
  # non-newline byte, then append exactly one newline. `head -c` keeps bytes
  # flowing file-to-file so NULs and invalid multibyte sequences survive --
  # nothing passes through a shell variable.
  rc=0
  body_bytes="$(LC_ALL=C wc -c < "$path")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'Error: %s: could not measure file; left unchanged\n' "$file" >&2
    cleanup
    return 0
  fi
  keep=$((body_bytes - nl))
  if [ "$keep" -lt 0 ]; then
    keep=0
  fi
  # Two separate steps rather than one `{ ...; } > "$TMPFILE"` group: an
  # `exit` inside such a group exits the SCRIPT, not the group, so a failing
  # `head` would bypass the exit-code contract below (measured: leaked head's
  # own status instead of 2). Redirect each command individually and check it.
  rc=0
  if [ "$keep" -gt 0 ]; then
    LC_ALL=C head -c "$keep" -- "$path" > "$TMPFILE" || rc=$?
  else
    : > "$TMPFILE" || rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    printf 'Error: %s: rewrite failed (exit %s); left unchanged\n' \
      "$file" "$rc" >&2
    cleanup
    return 0
  fi
  rc=0
  printf '\n' >> "$TMPFILE" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'Error: %s: could not append final newline (exit %s); left unchanged\n' \
      "$file" "$rc" >&2
    cleanup
    return 0
  fi

  # Sanity invariant. Byte and line counts legitimately change here (that is
  # the point of the hook), so the only usable check is that everything before
  # the final run of newlines is bit-identical. This is what catches a partial
  # write, a short read, a full disk, or a tool that exits 0 with wrong output.
  rc=0
  in_d="$(body_digest "$path")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'Error: %s: could not digest original; left unchanged\n' \
      "$file" >&2
    cleanup
    return 0
  fi
  rc=0
  out_d="$(body_digest "$TMPFILE")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'Error: %s: could not digest rewrite; left unchanged\n' \
      "$file" >&2
    cleanup
    return 0
  fi
  if [ "$in_d" != "$out_d" ]; then
    printf 'Error: %s: rewrite altered file content; left unchanged\n' \
      "$file" >&2
    cleanup
    return 0
  fi

  rc=0
  cmp -s "$TMPFILE" "$path" || rc=$?
  case "$rc" in
    0)
      # Byte-identical. The newline pre-check above means we should not get
      # here; kept so that an unexpected no-op can never trigger a needless
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
  # file's permissions as a side effect of a newline fix. The old code used
  # `|| true` here, which left such files at 0600.
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
  # Skip symlinks: we must not replace a symlink with a regular file. The old
  # version had no such guard and would clobber the link, copying the link's
  # own mode onto the resulting regular file.
  # Skip empty files: they have no final newline to fix and POSIX allows an
  # empty file to be valid.
  if [ -f "$file" ] && [ ! -L "$file" ] && [ -s "$file" ]; then
    fix_file "$file"
    case "$FIX_RESULT" in
      changed)
        printf 'Fixed end of file: %s\n' "$file" >&2
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
