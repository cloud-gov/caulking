#!/usr/bin/env bash
# Test that only staged files are scanned (unstaged secrets ignored)
set -euo pipefail

# shellcheck source=lib/test-helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/test-helpers.sh"

full_test_setup

# Create unstaged secret (should not trigger)
cat > unstaged_secret.txt << 'EOF'
aws_secret_access_key = WT8ftNba7siVx5UOoGzJSyd82uNCZAC8LCllzcWp
EOF

# Stage only clean file
echo "ok" > clean.txt
git add clean.txt

# Should pass since secret is unstaged
"$TEST_HOOK" > /dev/null
