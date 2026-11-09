#!/usr/bin/env bash
# check-large-files.sh - Check for files larger than specified size
#
# Usage: check-large-files.sh [--maxkb=SIZE]
# Default: 500KB
#
# CORRECTED: Fixed SC2046 word splitting vulnerability for filenames with spaces

set -euo pipefail

# Parse arguments
MAX_KB=500
for arg in "$@"; do
  case $arg in
    --maxkb=*)
      MAX_KB="${arg#*=}"
      # Validate numeric input
      if [[ ! "$MAX_KB" =~ ^[0-9]+$ ]]; then
        echo "ERROR: --maxkb must be a positive integer, got: $MAX_KB" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

MAX_BYTES=$((MAX_KB * 1024))
EXIT_CODE=0

# Use null-delimited output to handle filenames with spaces safely
while IFS= read -r -d '' file; do
  if [[ -f "$file" ]]; then
    size=$(wc -c < "$file")
    if ((size > MAX_BYTES)); then
      echo "ERROR: $file is $((size / 1024))KB (max: ${MAX_KB}KB)" >&2
      EXIT_CODE=1
    fi
  fi
done < <(git diff --cached --name-only --diff-filter=ACM -z 2> /dev/null || true)

exit $EXIT_CODE
