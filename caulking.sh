#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "setup" ]]; then
  shift
  [[ -r "$ROOT/install.sh" ]] || {
    printf 'caulking: missing installer: %s\n' "$ROOT/install.sh" >&2
    exit 2
  }
  exec "$BASH" "$ROOT/install.sh" "$@"
fi
# shellcheck source=scripts/toolchain.sh
source "$ROOT/scripts/toolchain.sh"

toolchain_main "$@"
