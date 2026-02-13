#!/usr/bin/env bash
# =====================================================================
# FILE: scripts/pretty.sh
# =====================================================================

set -euo pipefail

# Keep pretty self-contained. verify.sh sources it for nicer UX.

is_tty() { [[ -t 1 ]]; }

use_color() {
  [[ -z "${NO_COLOR:-}" ]] && is_tty
}

# Use unicode box drawing only when interactive and not explicitly disabled.
# Also avoid unicode when TERM=dumb (common in some CI/log contexts).
use_unicode() {
  [[ -z "${CAULKING_ASCII_BOX:-}" ]] && is_tty && [[ "${TERM:-}" != "dumb" ]]
}

RESET=""
BOLD=""
DIM=""
RED=""
GREEN=""
YELLOW=""
BLUE=""
MAGENTA=""
CYAN=""
GRAY=""

init_pretty() {
  if use_color; then
    RESET=$'\033[0m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    RED=$'\033[31m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    BLUE=$'\033[34m'
    MAGENTA=$'\033[35m'
    CYAN=$'\033[36m'
    GRAY=$'\033[90m'
  else
    RESET=""
    BOLD=""
    DIM=""
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
    GRAY=""
  fi
}
init_pretty

p_info() { printf '%b\n' "${CYAN}ℹ${RESET} $*"; }
p_ok() { printf '%b\n' "${GREEN}✔${RESET} $*"; }
p_warn() { printf '%b\n' "${YELLOW}⚠${RESET} $*"; }
p_err() { printf '%b\n' "${RED}✖${RESET} $*"; }

status_line() {
  local label="$1"
  local msg="$2"
  local color="${3:-$CYAN}"
  local dot="●"

  if ! use_color; then
    dot="*"
    color=""
  fi

  printf '  %s%s%s %s%-18s%s %s\n' \
    "$color" "$dot" "$RESET" \
    "$BOLD" "$label" "$RESET" \
    "$msg"
}

_draw_rule() {
  local color="$1"
  local left="$2"
  local hz="$3"
  local right="$4"
  local width="$5"

  printf '%s%s' "$color" "$left"
  local i=0
  for ((i = 0; i < width; i++)); do
    printf '%s' "$hz"
  done
  printf '%s%s\n' "$right" "$RESET"
}

# Return terminal display width (columns) for a string.
# - Uses python3 if available (stdlib only).
# - Falls back to bash length if python3 isn't present.
_disp_width() {
  local s="$1"

  if command -v python3 > /dev/null 2>&1; then
    python3 - "$s" << 'PY'
import sys, unicodedata

s = sys.argv[1]

def is_emoji(cp: int) -> bool:
    return (
        0x1F300 <= cp <= 0x1FAFF or
        0x2600  <= cp <= 0x26FF  or
        0x2700  <= cp <= 0x27BF  or
        0xFE00  <= cp <= 0xFE0F
    )

w = 0
for ch in s:
    cp = ord(ch)
    if ch == "\t":
        w += 4
        continue
    if ch in ("\n", "\r"):
        continue
    eaw = unicodedata.east_asian_width(ch)
    if eaw in ("W", "F"):
        w += 2
    elif is_emoji(cp):
        w += 2
    else:
        w += 1

print(w)
PY
    return 0
  fi

  printf '%s\n' "${#s}"
}

_pad_to() {
  local current="$1"
  local target="$2"
  local n=$((target - current))
  if ((n < 0)); then n=0; fi

  local i=0
  for ((i = 0; i < n; i++)); do
    printf ' '
  done
}

kv_list() {
  local max=0 line key val is_kv
  local -a keys=() vals=() kv=() keyw=()

  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      keys+=("")
      vals+=("")
      kv+=(0)
      keyw+=(0)
      continue
    fi

    is_kv=0
    if [[ "$line" == *:* ]]; then
      key="${line%%:*}"
      val="${line#*:}"
      val="${val# }"
      if [[ -n "$val" ]]; then
        is_kv=1
        local w
        w="$(_disp_width "$key")"
        ((w > max)) && max=$w
      fi
    fi

    if [[ "$is_kv" -eq 1 ]]; then
      keys+=("$key")
      vals+=("$val")
      kv+=(1)
      keyw+=("$(_disp_width "$key")")
    else
      keys+=("$line")
      vals+=("")
      kv+=(0)
      keyw+=(0)
    fi
  done

  local i
  for i in "${!keys[@]}"; do
    if [[ -z "${keys[$i]}" && "${kv[$i]}" -eq 0 ]]; then
      printf '\n'
      continue
    fi

    if [[ "${kv[$i]}" -eq 1 ]]; then
      printf -- "- %s" "${keys[$i]}"
      _pad_to "${keyw[$i]}" "$max"
      printf ' : %s\n' "${vals[$i]}"
    else
      printf -- "- %s\n" "${keys[$i]}"
    fi
  done
}

pretty_box() {
  local title="${1:-}"
  local color="${2:-$CYAN}"
  local extra_pad="${CAULKING_BOX_EXTRA_PAD:-0}"

  local tl tr bl br hz vt
  local sep_l sep_r
  if use_unicode; then
    tl="╭"
    tr="╮"
    bl="╰"
    br="╯"
    hz="─"
    vt="│"
    sep_l="├"
    sep_r="┤"
  else
    tl="+"
    tr="+"
    bl="+"
    br="+"
    hz="-"
    vt="|"
    sep_l="+"
    sep_r="+"
  fi

  local lines=()
  local line=""
  while IFS= read -r line; do
    lines+=("$line")
  done

  local max=0
  local lw=0
  local l=""
  for l in "${lines[@]}"; do
    lw="$(_disp_width "$l")"
    if ((lw > max)); then
      max=$lw
    fi
  done

  local width=$((max + 2 + extra_pad))

  if [[ -n "$title" ]]; then
    local tw
    tw="$(_disp_width "$title")"
    local title_needed=$((tw + 2 + extra_pad))
    if ((title_needed > width)); then
      width=$title_needed
    fi
  fi

  _draw_rule "$color" "$tl" "$hz" "$tr" "$width"

  if [[ -n "$title" ]]; then
    local tw
    tw="$(_disp_width "$title")"

    local inner=$((width - 2))
    local pad=$((inner - tw))
    if ((pad < 0)); then pad=0; fi

    printf '%s%s%s ' "$color" "$vt" "$RESET"
    printf '%s%s%s' "$BOLD" "$title" "$RESET"
    _pad_to "$tw" "$((tw + pad))"
    printf ' %s%s%s\n' "$color" "$vt" "$RESET"

    _draw_rule "$color" "$sep_l" "$hz" "$sep_r" "$width"
  fi

  for l in "${lines[@]}"; do
    local cw
    cw="$(_disp_width "$l")"
    local inner=$((width - 2))
    local pad=$((inner - cw))
    if ((pad < 0)); then pad=0; fi

    printf '%s%s%s ' "$color" "$vt" "$RESET"
    printf '%s' "$l"
    _pad_to "$cw" "$((cw + pad))"
    printf ' %s%s%s\n' "$color" "$vt" "$RESET"
  done

  _draw_rule "$color" "$bl" "$hz" "$br" "$width"
}
