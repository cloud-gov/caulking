#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib.sh"

on_err_trap
enable_xtrace_if_debug

# - gitleaks is REQUIRED
# - prek is OPTIONAL
MIN_GITLEAKS_VERSION="${MIN_GITLEAKS_VERSION:-8.18.0}"

ensure_gitleaks() {
  if have gitleaks; then
    info "gitleaks already installed: $(command -v gitleaks)"
  else
    if have brew; then
      info "Installing gitleaks via Homebrew (best-effort)..."
      # Avoid failing install if brew has transient issues; we verify afterward.
      brew upgrade gitleaks > /dev/null 2>&1 || true
      brew install gitleaks > /dev/null 2>&1 || true
    else
      die "gitleaks not found and Homebrew is not available. Install gitleaks v8+."
    fi
  fi

  have gitleaks || die "gitleaks is still not available after install attempt"
  info "gitleaks path: $(command -v gitleaks)"

  local out v
  out="$(gitleaks version 2> /dev/null || true)"
  [[ -n "$out" ]] || die "gitleaks failed to run"
  info "gitleaks version: $out"

  # gitleaks version output is usually "... <ver>" where <ver> might be "v8.30.0" or "8.30.0"
  v="$(printf '%s\n' "$out" | awk '{print $NF}' | tr -d '[:space:]')"
  v="$(strip_v_prefix "$v")"
  [[ -n "$v" ]] || die "Could not parse gitleaks version from: $out"

  if ! version_ge "$v" "$MIN_GITLEAKS_VERSION"; then
    die "gitleaks too old: $v < $MIN_GITLEAKS_VERSION"
  fi
}

ensure_prek_optional() {
  if have prek; then
    info "prek already installed: $(command -v prek)"
    prek --version || true
    return 0
  fi

  if have uv; then
    info "Installing prek via uv tool..."
    uv tool install prek || true
  fi

  if ! have prek && have brew; then
    info "Installing prek via Homebrew..."
    brew install prek > /dev/null 2>&1 || true
  fi

  if have prek; then
    info "prek installed: $(command -v prek)"
    prek --version || true
  else
    warn "prek not installed (optional). Repo-level hooks via .pre-commit-config.yaml will be skipped."
  fi
}

main() {
  ensure_gitleaks
  ensure_prek_optional
}

main "$@"
