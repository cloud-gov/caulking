#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Caulking shared bash library (KISS)
# - logging helpers
# - debug helpers
# - consistent error handling
# - XDG path helpers
# ==============================================================================

# NOTE: This file is intended to be sourced by repo scripts, not executed directly.

is_tty() { [[ -t 1 ]]; }

want_debug() { [[ "${CAULKING_DEBUG:-0}" != "0" ]]; }

_now() {
  # ISO-8601 UTC-ish timestamp (no external deps)
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2> /dev/null || date
}

log() { printf '%s %s\n' "$(_now)" "$*"; }
info() { log "INFO: $*"; }
warn() { log "WARN: $*" >&2; }
err() { log "ERROR: $*" >&2; }

die() {
  err "$*"
  exit 2
}

have() { command -v "$1" > /dev/null 2>&1; }

need_cmd() {
  have "$1" || die "Missing required command: $1"
}

# Safer sourcing helper
safe_source() {
  local f="$1"
  [[ -f "$f" ]] || die "Missing required file: $f"
  # shellcheck source=/dev/null
  source "$f"
}

# Debug print + optional xtrace
debug() {
  want_debug || return 0
  err "DEBUG: $*"
}

enable_xtrace_if_debug() {
  want_debug || return 0
  # avoid noisy traces for non-interactive unless explicitly requested
  set -x
}

# Error trap that prints useful context. Call this once in scripts that want it.
# Example:
#   on_err_trap
on_err_trap() {
  # shellcheck disable=SC2154
  trap '__caulking_on_err $? ${LINENO} "${BASH_COMMAND:-}" "${BASH_SOURCE[0]:-}"' ERR
}

__caulking_on_err() {
  local rc="$1" line="$2" cmd="$3" src="$4"
  want_debug || return "$rc"
  err "DEBUG: failed rc=$rc file=$src line=$line cmd=$cmd"
  return "$rc"
}

# XDG helpers
xdg_config_home() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}"; }
caulking_state_dir() { printf '%s\n' "$(xdg_config_home)/caulking"; }
git_hook_dir() { printf '%s\n' "$(xdg_config_home)/git/hooks"; }
gitleaks_cfg_path() { printf '%s\n' "$(xdg_config_home)/gitleaks/config.toml"; }
gitleaks_cfg_dir() { printf '%s\n' "$(xdg_config_home)/gitleaks"; }
prev_hookspath_file() { printf '%s\n' "$(caulking_state_dir)/previous_hookspath"; }

# Export standard XDG paths for Caulking installation.
# Usage: eval "$(caulking_export_paths)"
# Sets: XDG_CONFIG_HOME, HOOK_DIR, GITLEAKS_DIR, GITLEAKS_CFG, STATE_DIR, PREV_HOOKSPATH_FILE
caulking_export_paths() {
  cat << 'PATHS'
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
HOOK_DIR="$XDG_CONFIG_HOME/git/hooks"
GITLEAKS_DIR="$XDG_CONFIG_HOME/gitleaks"
GITLEAKS_CFG="$GITLEAKS_DIR/config.toml"
STATE_DIR="$XDG_CONFIG_HOME/caulking"
PREV_HOOKSPATH_FILE="$STATE_DIR/previous_hookspath"
PATHS
}

# Normalize "v8.30.0" -> "8.30.0"
strip_v_prefix() {
  local v="$1"
  v="${v#v}"
  printf '%s\n' "$v"
}

# Compare semver-ish: returns 0 if v >= min
# Accepts "8.30.0" and similar; ignores suffixes.
version_ge() {
  local v_raw="$1" min_raw="$2"
  local v min
  v="$(strip_v_prefix "$v_raw")"
  min="$(strip_v_prefix "$min_raw")"

  # Split into MA.MIN.PATCH (missing parts become 0)
  local v_ma=0 v_mi=0 v_pa=0
  local m_ma=0 m_mi=0 m_pa=0

  IFS='.' read -r v_ma v_mi v_pa _ <<< "${v}"
  IFS='.' read -r m_ma m_mi m_pa _ <<< "${min}"

  v_ma="${v_ma:-0}"
  v_mi="${v_mi:-0}"
  v_pa="${v_pa:-0}"
  m_ma="${m_ma:-0}"
  m_mi="${m_mi:-0}"
  m_pa="${m_pa:-0}"

  # Force numeric compare; if any are non-numeric, fail closed
  [[ "$v_ma" =~ ^[0-9]+$ && "$v_mi" =~ ^[0-9]+$ && "$v_pa" =~ ^[0-9]+$ ]] || return 1
  [[ "$m_ma" =~ ^[0-9]+$ && "$m_mi" =~ ^[0-9]+$ && "$m_pa" =~ ^[0-9]+$ ]] || return 1

  if ((v_ma > m_ma)); then return 0; fi
  if ((v_ma < m_ma)); then return 1; fi
  if ((v_mi > m_mi)); then return 0; fi
  if ((v_mi < m_mi)); then return 1; fi
  ((v_pa >= m_pa))
}
