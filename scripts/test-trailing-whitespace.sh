#!/usr/bin/env bash
# test-trailing-whitespace.sh — behavioral tests for scripts/trailing-whitespace.sh
#
# Regression suite for the data-destruction bug shipped in v0.6.1: BSD sed
# SIGABRTs on NUL bytes and the script never checked its exit status, so it
# `mv`d an empty temp file over the original. Root cause was broader than NUL —
# the rewrite ran in a subshell on the LHS of a pipeline, where bash suspends
# `set -e`, so ANY sed failure installed partial output.
#
# Invariant under test: a file is either fully rewritten or left BYTE-IDENTICAL.
#
# Follows the working pattern from test-validate-hooks.sh — note `PASS=$((PASS + 1))`,
# not `((PASS++))`, which returns 1 when PASS=0 and kills the suite under `set -e`
# (that is why scripts/test-hooks.sh dies at its first passing test).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXER="$REPO_ROOT/scripts/trailing-whitespace.sh"

PASS=0
FAIL=0

tmp="$(mktemp -d)"
# Tests chmod a directory to 555 to force mktemp failure; make sure teardown can
# still remove it even if a test aborts early.
cleanup() {
  chmod -R u+rwX "$tmp" 2> /dev/null || true
  rm -rf "$tmp"
}
trap 'cleanup' EXIT

ok() {
  echo "  ok: $1"
  PASS=$((PASS + 1))
}

bad() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}

check() { # check DESC ACTUAL EXPECTED
  if [ "$2" = "$3" ]; then
    ok "$1 ($2)"
  else
    bad "$1 (expected '$3', got '$2')"
  fi
}

hex() { xxd -p "$1" | tr -d '\n'; }

# Digest form, for files too big to print a full hex dump of on failure.
sum_of() { cksum < "$1"; }

bytes() { LC_ALL=C wc -c < "$1" | tr -d ' '; }

inode() { stat -c '%i' "$1" 2> /dev/null || stat -f '%i' "$1"; }

mode_of() { stat -c '%a' "$1" 2> /dev/null || stat -f '%Lp' "$1" 2> /dev/null; }

# listing DIR [EXCLUDE] -> sorted space-separated basenames of DIR, minus EXCLUDE.
# Detects temp files the fixer failed to clean up.
listing() {
  local d="$1" exclude="${2:-}" p n out=""
  for p in "$d"/* "$d"/.*; do
    n="$(basename "$p")"
    case "$n" in
      '*' | '.*' | '.' | '..') continue ;;
    esac
    [ -n "$exclude" ] && [ "$n" = "$exclude" ] && continue
    out="$out$n "
  done
  printf '%s' "$out"
}

# run DIR -> sets RC; runs the fixer with the remaining args, cwd = DIR
run() {
  local d="$1"
  shift
  RC=0
  (cd "$d" && "$FIXER" "$@") || RC=$?
}

# run_stub DIR STUBDIR -> like run() but with STUBDIR prepended to PATH
run_stub() {
  local d="$1" stub="$2"
  shift 2
  RC=0
  (cd "$d" && PATH="$stub:$PATH" "$FIXER" "$@") || RC=$?
}

# mkcase NAME -> echoes a fresh case dir
mkcase() {
  local d="$tmp/$1"
  mkdir -p "$d"
  printf '%s' "$d"
}

# mkstub DIR SCRIPT -> writes an executable `sed` stub into DIR/stub
mkstub() {
  local stub="$1/stub"
  mkdir -p "$stub"
  printf '%s\n' "$2" > "$stub/sed"
  chmod +x "$stub/sed"
  printf '%s' "$stub"
}

echo "trailing-whitespace.sh data-loss regressions:"

# --- 1. NUL bytes: file must not lose a single byte -------------------------
# The exact v0.6.1 reproduction: 30 bytes -> 0 bytes with "Fixed" reported.
d="$(mkcase nul)"
printf 'has\000nul and ws   \nsecond line\n' > "$d/f.bin"
before="$(hex "$d/f.bin")"
run "$d" f.bin
check "NUL file: bytes unchanged" "$(hex "$d/f.bin")" "$before"
check "NUL file: byte count unchanged" "$(bytes "$d/f.bin")" "30"
check "NUL file: exit 0 (skipped, not an error)" "$RC" "0"

# NUL beyond identify()'s 1024-byte sniff window — how a binary reaches a
# types:[text] hook in the first place.
d="$(mkcase nul_late)"
{
  head -c 2000 /dev/zero | tr '\000' 'a'
  printf '   \n\000\000tail\n'
} > "$d/late.bin"
before="$(sum_of "$d/late.bin")"
beforebytes="$(bytes "$d/late.bin")"
run "$d" late.bin
check "late-NUL file: bytes unchanged" "$(sum_of "$d/late.bin")" "$before"
check "late-NUL file: byte count unchanged" "$(bytes "$d/late.bin")" "$beforebytes"
check "late-NUL file: exit 0" "$RC" "0"

# A NUL file with nothing to strip is not even scanned: silent, exit 0.
d="$(mkcase nul_clean)"
printf 'has\000nul but no ws\n' > "$d/c.bin"
before="$(hex "$d/c.bin")"
run "$d" c.bin
check "clean NUL file: bytes unchanged" "$(hex "$d/c.bin")" "$before"
check "clean NUL file: exit 0" "$RC" "0"

# --- 2. sed failure via PATH stub ------------------------------------------
# Partial output + non-zero status: this truncated 52 bytes to 7 before the fix.
d="$(mkcase sed_partial)"
stub="$(mkstub "$d" '#!/bin/sh
printf PARTIAL
exit 4')"
printf 'line one with ws   \nline two\nline three here\n' > "$d/s.txt"
before="$(hex "$d/s.txt")"
run_stub "$d" "$stub" s.txt
check "sed exit 4: original byte-identical" "$(hex "$d/s.txt")" "$before"
check "sed exit 4: non-zero exit" "$([ "$RC" -ne 0 ] && echo yes || echo no)" "yes"

# Silent failure, empty output: this zeroed the file before the fix.
d="$(mkcase sed_silent)"
stub="$(mkstub "$d" '#!/bin/sh
exit 1')"
printf 'ws here   \nmore content\n' > "$d/s.txt"
before="$(hex "$d/s.txt")"
run_stub "$d" "$stub" s.txt
check "sed exit 1 (silent): original byte-identical" "$(hex "$d/s.txt")" "$before"
check "sed exit 1 (silent): non-zero exit" "$([ "$RC" -ne 0 ] && echo yes || echo no)" "yes"

# A truncating sed that exits 0. There is no exit status to check, so the output
# invariants (line count, byte ceiling, content digest) are the only guard.
d="$(mkcase sed_lying)"
stub="$(mkstub "$d" '#!/bin/sh
printf "x\n"
exit 0')"
printf 'ws here   \nmore\nlines\n' > "$d/s.txt"
before="$(hex "$d/s.txt")"
run_stub "$d" "$stub" s.txt
check "sed exit 0 but truncated: original byte-identical" "$(hex "$d/s.txt")" "$before"
check "sed exit 0 but truncated: non-zero exit" "$([ "$RC" -ne 0 ] && echo yes || echo no)" "yes"

# Nastiest case: a sed whose output keeps the line count AND stays under the
# byte ceiling, so only the content digest can tell it truncated.
d="$(mkcase sed_subtle)"
stub="$(mkstub "$d" '#!/bin/sh
printf "a\n"
exit 0')"
printf 'aaaaaaa   \n' > "$d/s.txt"
before="$(hex "$d/s.txt")"
run_stub "$d" "$stub" s.txt
check "sed truncating within the byte/line budget: original byte-identical" "$(hex "$d/s.txt")" "$before"
check "sed truncating within the byte/line budget: non-zero exit" "$([ "$RC" -ne 0 ] && echo yes || echo no)" "yes"

# --- 3. mktemp failure must fail CLOSED -----------------------------------
# Before the fix this failed OPEN: subshell exit 2 was swallowed by `grep -q`
# and the hook reported success on an unfixed file.
d="$(mkcase mktemp_fail)"
mkdir -p "$d/ro"
printf 'needs fixing   \n' > "$d/ro/h.txt"
before="$(hex "$d/ro/h.txt")"
chmod 555 "$d/ro"
run "$d" ro/h.txt
chmod 755 "$d/ro"
check "mktemp failure: file unchanged" "$(hex "$d/ro/h.txt")" "$before"
check "mktemp failure: non-zero exit" "$([ "$RC" -ne 0 ] && echo yes || echo no)" "yes"

# A clean file needs no temp file at all, so a read-only directory is fine.
d="$(mkcase readonly_clean)"
mkdir -p "$d/ro"
printf 'already clean\n' > "$d/ro/c.txt"
chmod 555 "$d/ro"
run "$d" ro/c.txt
chmod 755 "$d/ro"
check "clean file in read-only dir: exit 0" "$RC" "0"

echo ""
echo "trailing-whitespace.sh behavior preserved:"

# --- 4. happy path --------------------------------------------------------
d="$(mkcase happy)"
printf 'a   \nb\t\t\nc\n' > "$d/g.txt"
run "$d" g.txt
check "trailing whitespace removed" "$(hex "$d/g.txt")" "610a620a630a"
check "fixer contract: exit 1 when a file was modified" "$RC" "1"

# --- 5. idempotence ------------------------------------------------------
i1="$(inode "$d/g.txt")"
m1="$(stat -c '%Y' "$d/g.txt" 2> /dev/null || stat -f '%m' "$d/g.txt")"
sleep 1
run "$d" g.txt
check "second run: exit 0" "$RC" "0"
check "second run: inode unchanged" "$(inode "$d/g.txt")" "$i1"
m2="$(stat -c '%Y' "$d/g.txt" 2> /dev/null || stat -f '%m' "$d/g.txt")"
check "second run: mtime unchanged" "$m2" "$m1"

# --- 6. mode preservation -------------------------------------------------
d="$(mkcase modes)"
printf 'x   \n' > "$d/m755.txt"
chmod 755 "$d/m755.txt"
printf 'x   \n' > "$d/m664.txt"
chmod 664 "$d/m664.txt"
run "$d" m755.txt m664.txt
check "mode 0755 preserved across fix" "$(mode_of "$d/m755.txt")" "755"
check "mode 0664 preserved across fix" "$(mode_of "$d/m664.txt")" "664"
check "both files fixed" "$(hex "$d/m755.txt")$(hex "$d/m664.txt")" "780a780a"

# --- 7. symlink guard ----------------------------------------------------
d="$(mkcase symlink)"
printf 'tgt   \n' > "$d/tgt.txt"
(cd "$d" && ln -s tgt.txt link.txt)
run "$d" link.txt
check "symlink still a symlink" "$([ -L "$d/link.txt" ] && echo yes || echo no)" "yes"
check "symlink target untouched" "$(hex "$d/tgt.txt")" "7467742020200a"
check "symlink: exit 0" "$RC" "0"

# --- 8. no temp files left behind ---------------------------------------
d="$(mkcase leftovers)"
printf 'ws   \n' > "$d/a.txt"
printf 'clean\n' > "$d/b.txt"
run "$d" a.txt b.txt
check "no temp files left behind" "$(listing "$d")" "a.txt b.txt "

# Also after a failure path — the trap must still fire.
d="$(mkcase leftovers_fail)"
stub="$(mkstub "$d" '#!/bin/sh
exit 9')"
printf 'ws   \n' > "$d/a.txt"
run_stub "$d" "$stub" a.txt
check "no temp files left behind after failure" "$(listing "$d" stub)" "a.txt "

# --- 9. multi-file: one bad file must not stop the others ---------------
d="$(mkcase multi)"
printf 'ok ws   \n' > "$d/good.txt"
printf 'bin\000nul   \n' > "$d/bad.bin"
binbefore="$(hex "$d/bad.bin")"
run "$d" bad.bin good.txt
check "good file still fixed alongside a skipped binary" "$(hex "$d/good.txt")" "6f6b2077730a"
check "skipped binary untouched" "$(hex "$d/bad.bin")" "$binbefore"
check "multi-file: exit 1 (a file changed)" "$RC" "1"

# --- 10. awkward filenames ---------------------------------------------
# A leading dash is parsed as an option by mktemp/chmod/mv; BSD sed rejects "--",
# so the script prefixes "./" instead. Before this, mktemp failed on such files.
d="$(mkcase dashname)"
printf 'ws   \nb\n' > "$d/-lead.txt"
run "$d" -lead.txt
check "leading-dash filename fixed" "$(hex "$d/-lead.txt")" "77730a620a"
check "leading-dash filename: exit 1" "$RC" "1"
check "leading-dash: no temp file left" "$(listing "$d")" "-lead.txt "

d="$(mkcase spacename)"
printf 'ws   \n' > "$d/we ird\$name.txt"
run "$d" "we ird\$name.txt"
check "filename with space and \$ fixed" "$(hex "$d/we ird\$name.txt")" "77730a"

echo ""
echo "trailing-whitespace tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
