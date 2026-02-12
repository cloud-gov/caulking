#!/usr/bin/env bash
set -euo pipefail

# - gitleaks is REQUIRED
# - prek is OPTIONAL
MIN_GITLEAKS_VERSION="${MIN_GITLEAKS_VERSION:-8.18.0}"

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }

version_ge() {
  local v="$1" min="$2"
  local v_ma v_mi v_pa min_ma min_mi min_pa rest

  v_ma="${v%%.*}"; rest="${v#*.}"; v_mi="${rest%%.*}"; v_pa="${rest#*.}"
  min_ma="${min%%.*}"; rest="${min#*.}"; min_mi="${rest%%.*}"; min_pa="${rest#*.}"

  if [[ "$v_ma" -gt "$min_ma" ]]; then return 0; fi
  if [[ "$v_ma" -lt "$min_ma" ]]; then return 1; fi
  if [[ "$v_mi" -gt "$min_mi" ]]; then return 0; fi
  if [[ "$v_mi" -lt "$min_mi" ]]; then return 1; fi
  [[ "$v_pa" -ge "$min_pa" ]]
}

ensure_gitleaks() {
  if have gitleaks; then
    say "gitleaks already installed: $(command -v gitleaks)"
  else
    if have brew; then
      say "Installing gitleaks via Homebrew (best-effort)..."
      brew upgrade gitleaks >/dev/null 2>&1 || true
      brew install gitleaks >/dev/null 2>&1 || true
    else
      die "gitleaks not found and Homebrew is not available. Install gitleaks v8+."
    fi
  fi

  say "gitleaks path: $(command -v gitleaks)"
  say "gitleaks version:"
  gitleaks version

  local v
  v="$(gitleaks version | awk '{print $NF}')"
  if ! version_ge "$v" "$MIN_GITLEAKS_VERSION"; then
    die "gitleaks too old: $v < $MIN_GITLEAKS_VERSION"
  fi
}

ensure_prek_optional() {
  if have prek; then
    say "prek already installed: $(command -v prek)"
    prek --version || true
    return 0
  fi

  if have uv; then
    say "Installing prek via uv tool..."
    uv tool install prek || true
  fi

  if ! have prek && have brew; then
    say "Installing prek via Homebrew..."
    brew install prek >/dev/null 2>&1 || true
  fi

  if have prek; then
    say "prek installed: $(command -v prek)"
    prek --version || true
  else
    say "NOTE: prek not installed (optional). Repo-level hooks via .pre-commit-config.yaml will be skipped."
  fi
}

main() {
  ensure_gitleaks
  ensure_prek_optional
}

main "$@"
