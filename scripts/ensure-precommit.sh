#!/usr/bin/env bash
# Ensure pre-commit hooks are installed & up to date in the current repo.
# Idempotent. macOS/Linux. ShellCheck-clean.

set -euo pipefail

if ! command -v uv >/dev/null 2>&1; then
  printf 'error: uv not found. Install uv first.\n' >&2
  exit 2
fi

# Ensure pre-commit exists in this env
uv run python -c "import sys; import importlib; sys.exit(0 if importlib.util.find_spec('pre_commit') else 1)" \
  || uv pip install pre-commit >/dev/null

# Install or refresh hooks (pre-commit + pre-push)
uv run pre-commit install -t pre-commit -t pre-push

# Optional: autoupdate pinned hook versions when called with --update
if [[ "${1:-}" == "--update" ]]; then
  uv run pre-commit autoupdate
fi

echo "pre-commit is installed and ready."
