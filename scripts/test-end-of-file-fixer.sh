#!/usr/bin/env bash
# test-end-of-file-fixer.sh — behavioral tests for scripts/end-of-file-fixer.sh
#
# Regression suite for the data-loss bugs shipped in v0.6.1:
#   1. `content=$(cat "$file")` — bash DISCARDS NUL bytes in command
#      substitution, so any file containing one was silently rewritten without
#      it. Measured: 6100620a63 -> 61620a630a, SAME byte count, exit 0. A
#      size-based check cannot see this; only a content digest can.
#   2. The rewrite ran in `( ... ) || exit 1`, and bash suspends `set -e` on the
#      left of `||`, so `cat`'s status was never checked. A stub cat printing
#      "PART" and exiting 5 turned 31 bytes into 5, exit 0.
#
# Invariant under test: a file is either fully rewritten or left BYTE-IDENTICAL.
#
# Follows the working pattern from test-validate-hooks.sh — note `PASS=$((PASS + 1))`,
# not `((PASS++))`, which returns 1 when PASS=0 and kills the suite under `set -e`
# (that is why scripts/test-hooks.sh dies at its first passing test).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXER="$REPO_ROOT/scripts/end-of-file-fixer.sh"

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

sum_of() { cksum < "$1"; }

bytes() { LC_ALL=C wc -c < "$1" | tr -d ' '; }

inode() { stat -c '%i' "$1" 2> /dev/null || stat -f '%i' "$1"; }

mtime_of() { stat -c '%Y' "$1" 2> /dev/null || stat -f '%m' "$1" 2> /dev/null; }

mode_of() { stat -c '%a' "$1" 2> /dev/null || stat -f '%Lp' "$1" 2> /dev/null; }

# listing DIR [EXCLUDE] -> sorted space-separated basenames, minus EXCLUDE.
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

run() {
  local d="$1"
  shift
  RC=0
  (cd "$d" && "$FIXER" "$@") || RC=$?
}

run_stub() {
  local d="$1" stub="$2"
  shift 2
  RC=0
  (cd "$d" && PATH="$stub:$PATH" "$FIXER" "$@") || RC=$?
}

mkcase() {
  local d="$tmp/$1"
  mkdir -p "$d"
  printf '%s' "$d"
}

# mkstub DIR NAME BODY -> creates an executable stub NAME in DIR
mkstub() {
  local d="$1" name="$2" body="$3"
  mkdir -p "$d"
  printf '#!/bin/sh\n%s\n' "$body" > "$d/$name"
  chmod +x "$d/$name"
}

echo "== the shipped v0.6.1 data-loss cases =="

d="$(mkcase nul_early)"
printf 'a\0b\nc' > "$d/f.bin"
before="$(hex "$d/f.bin")"
run "$d" f.bin
check "NUL early: bytes untouched" "$(hex "$d/f.bin")" "$before"
check "NUL early: exit 0 (skip is not a failure)" "$RC" "0"

# identify() only sniffs the first 1024 bytes, so a NUL past that still reaches
# the hook via types: [text]. This is the case that made the bug reachable.
d="$(mkcase nul_late)"
{
  head -c 1100 /dev/zero | tr '\0' 'x'
  printf '\0tail\n\n\n'
} > "$d/late.bin"
before="$(sum_of "$d/late.bin")"
beforeb="$(bytes "$d/late.bin")"
run "$d" late.bin
check "NUL past 1024B: content untouched" "$(sum_of "$d/late.bin")" "$before"
check "NUL past 1024B: size untouched" "$(bytes "$d/late.bin")" "$beforeb"
check "NUL past 1024B: exit 0" "$RC" "0"

echo "== rewrite-tool failures must never install partial output =="

# A tool that fails loudly.
d="$(mkcase head_fails)"
stub="$tmp/stub_fail"
mkstub "$stub" head 'printf PART
exit 5'
printf 'this is thirty one bytes long!!\n\n\n' > "$d/i.txt"
before="$(hex "$d/i.txt")"
run_stub "$d" "$stub" i.txt
check "head exit 5: bytes untouched" "$(hex "$d/i.txt")" "$before"
check "head exit 5: exit 2 (error, not 'fixed')" "$RC" "2"
check "head exit 5: no temp left behind" "$(listing "$d" i.txt)" ""

# A tool that LIES: exits 0 with wrong output. Neither byte count nor line count
# can catch this, because this hook legitimately changes both. Only the
# body digest can.
d="$(mkcase head_lies)"
stub="$tmp/stub_lie"
mkstub "$stub" head 'printf WRONGBODY
exit 0'
printf 'correct body here\n\n\n' > "$d/j.txt"
before="$(hex "$d/j.txt")"
run_stub "$d" "$stub" j.txt
check "head lies (exit 0, wrong bytes): untouched" "$(hex "$d/j.txt")" "$before"
check "head lies: exit 2" "$RC" "2"
check "head lies: no temp left behind" "$(listing "$d" j.txt)" ""

# A truncation that stays plausible: fewer bytes, still ends in a newline.
d="$(mkcase head_short)"
stub="$tmp/stub_short"
mkstub "$stub" head 'printf "cor\n"
exit 0'
printf 'correct body here\n\n\n' > "$d/k.txt"
before="$(hex "$d/k.txt")"
run_stub "$d" "$stub" k.txt
check "head truncates plausibly: untouched" "$(hex "$d/k.txt")" "$before"
check "head truncates plausibly: exit 2" "$RC" "2"

echo "== mktemp must fail CLOSED =="

d="$(mkcase mktemp_ro)"
printf 'needs a newline' > "$d/m.txt"
before="$(hex "$d/m.txt")"
chmod 555 "$d"
run "$d" m.txt
chmod 755 "$d"
check "read-only dir: bytes untouched" "$(hex "$d/m.txt")" "$before"
check "read-only dir: exit 2, not 0" "$RC" "2"

# A file that needs no fix must still succeed in a read-only directory, because
# the pre-check is read-only and never reaches mktemp.
d="$(mkcase mktemp_ro_clean)"
printf 'already fine\n' > "$d/c.txt"
chmod 555 "$d"
run "$d" c.txt
chmod 755 "$d"
check "read-only dir, clean file: exit 0" "$RC" "0"

echo "== the actual job =="

d="$(mkcase add_newline)"
printf 'no newline' > "$d/a.txt"
run "$d" a.txt
check "missing final newline added" "$(hex "$d/a.txt")" "6e6f206e65776c696e650a"
check "missing final newline: exit 1 (fixer contract)" "$RC" "1"

d="$(mkcase collapse)"
printf 'x\n\n\n\n' > "$d/b.txt"
run "$d" b.txt
check "multiple trailing newlines collapsed" "$(hex "$d/b.txt")" "780a"
check "collapse: exit 1" "$RC" "1"

d="$(mkcase crlf_tail)"
printf 'line\r\n\r\n\r\n' > "$d/c.txt"
run "$d" c.txt
check "CRLF tail: only trailing LFs collapse, CRs preserved" \
  "$(hex "$d/c.txt")" "6c696e650d0a0d0a0d0a"
check "CRLF tail: exit 0 (nothing this hook owns)" "$RC" "0"

d="$(mkcase single_nl)"
printf '\n' > "$d/d.txt"
run "$d" d.txt
check "file that is a single newline: unchanged" "$(hex "$d/d.txt")" "0a"
check "single newline: exit 0" "$RC" "0"

d="$(mkcase only_newlines)"
printf '\n\n\n' > "$d/e.txt"
run "$d" e.txt
check "file of only newlines collapses to one" "$(hex "$d/e.txt")" "0a"
check "only newlines: exit 1" "$RC" "1"

d="$(mkcase empty)"
: > "$d/f.txt"
run "$d" f.txt
check "empty file untouched" "$(bytes "$d/f.txt")" "0"
check "empty file: exit 0" "$RC" "0"

echo "== idempotence: a compliant file must not be rewritten =="

d="$(mkcase idem)"
printf 'fine\n' > "$d/g.txt"
i1="$(inode "$d/g.txt")"
m1="$(mtime_of "$d/g.txt")"
sleep 1
run "$d" g.txt
check "already correct: exit 0" "$RC" "0"
check "already correct: inode unchanged (no rewrite)" "$(inode "$d/g.txt")" "$i1"
check "already correct: mtime unchanged (no rewrite)" "$(mtime_of "$d/g.txt")" "$m1"

d="$(mkcase idem2)"
printf 'needs fix' > "$d/h.txt"
run "$d" h.txt
check "first run fixes" "$RC" "1"
i1="$(inode "$d/h.txt")"
run "$d" h.txt
check "second run is a no-op" "$RC" "0"
check "second run: inode unchanged" "$(inode "$d/h.txt")" "$i1"

echo "== attributes must survive the atomic replace =="

d="$(mkcase mode755)"
printf '#!/bin/sh\necho hi' > "$d/x.sh"
chmod 755 "$d/x.sh"
run "$d" x.sh
check "mode 0755 preserved" "$(mode_of "$d/x.sh")" "755"
check "mode 0755: file was fixed" "$RC" "1"

d="$(mkcase mode664)"
printf 'data' > "$d/y.txt"
chmod 664 "$d/y.txt"
run "$d" y.txt
check "mode 0664 preserved" "$(mode_of "$d/y.txt")" "664"

echo "== symlinks must not be clobbered =="

d="$(mkcase symlink)"
printf 'target needs fix' > "$d/target.txt"
chmod 600 "$d/target.txt"
(cd "$d" && ln -s target.txt link.txt)
run "$d" link.txt
if [ -L "$d/link.txt" ]; then
  ok "symlink still a symlink (not replaced by a regular file)"
else
  bad "symlink was replaced by a regular file"
fi
check "symlink: target untouched" "$(hex "$d/target.txt")" "$(printf 'target needs fix' | xxd -p | tr -d '\n')"
check "symlink: exit 0 (skipped)" "$RC" "0"

echo "== multi-file behaviour =="

# One unfixable file must not stop the others, and the error status must win.
d="$(mkcase multi)"
printf 'a\0b' > "$d/bad.bin"
printf 'good' > "$d/good.txt"
printf 'also' > "$d/also.txt"
run "$d" bad.bin good.txt also.txt
check "multi: good.txt still fixed" "$(hex "$d/good.txt")" "676f6f640a"
check "multi: also.txt still fixed" "$(hex "$d/also.txt")" "616c736f0a"
check "multi: NUL file untouched" "$(hex "$d/bad.bin")" "610062"
check "multi: exit 1 (a fix happened, skip is not an error)" "$RC" "1"

echo "== awkward filenames =="

d="$(mkcase dashname)"
printf 'lead' > "$d/-lead.txt"
run "$d" -lead.txt
check "leading-dash filename fixed" "$(hex "$d/-lead.txt")" "6c6561640a"
check "leading-dash: exit 1" "$RC" "1"

d="$(mkcase spacename)"
printf 'sp' > "$d/a b \$c.txt"
run "$d" "a b \$c.txt"
check "filename with space and \$ fixed" "$(hex "$d/a b \$c.txt")" "73700a"

echo ""
echo "end-of-file-fixer tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
