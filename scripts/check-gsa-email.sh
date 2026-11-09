#!/usr/bin/env bash
# check-gsa-email.sh — Ensure commits use @gsa.gov email addresses
#
# This hook checks:
# 1. Author email is @gsa.gov
# 2. Co-authored-by trailers use @gsa.gov
#
# For cloud.gov repositories that require federal employee attribution.

set -euo pipefail

EXIT_CODE=0

# Check author email
AUTHOR_EMAIL=$(git config user.email || echo "")
if [[ -n "$AUTHOR_EMAIL" && ! "$AUTHOR_EMAIL" =~ @gsa\.gov$ ]]; then
  echo "ERROR: Author email must be @gsa.gov" >&2
  echo "  Current: $AUTHOR_EMAIL" >&2
  echo "  Fix with: git config user.email 'your.name@gsa.gov'" >&2
  EXIT_CODE=1
fi

# Check staged commit message for Co-authored-by with non-gsa.gov emails
# This runs during commit-msg stage, checking the commit message file
if [[ -n "${1:-}" && -f "$1" ]]; then
  # Extract Co-authored-by lines and check emails
  while IFS= read -r line; do
    if [[ "$line" =~ Co-authored-by:.*\<([^>]+)\> ]]; then
      email="${BASH_REMATCH[1]}"
      if [[ ! "$email" =~ @gsa\.gov$ ]]; then
        echo "ERROR: Co-authored-by email must be @gsa.gov" >&2
        echo "  Found: $email" >&2
        echo "  Use: Co-authored-by: Name <name@gsa.gov>" >&2
        EXIT_CODE=1
      fi
    fi
  done < "$1"
fi

exit $EXIT_CODE
