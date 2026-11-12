#!/usr/bin/env bash
# check-merge-conflict.sh - Prevents committing unresolved merge conflicts
# Checks for Git conflict markers: <<<<<<<, =======, >>>>>>>

set -euo pipefail

# If no files passed, exit success (nothing to check)
if [[ $# -eq 0 ]]; then
  exit 0
fi

EXIT_CODE=0

for file in "$@"; do
  if [[ -f "$file" ]]; then
    # Search for conflict markers (7 consecutive chars)
    if grep -nE "^(<{7}|={7}|>{7})" "$file"; then
      echo "ERROR: Found merge conflict markers in $file"
      EXIT_CODE=1
    fi
  fi
done

exit $EXIT_CODE
