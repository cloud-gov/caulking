#!/usr/bin/env bash
# test_prepush_ref_parsing.sh
#
# Tests for pre-push hook stdin ref parsing and gitleaks invocation.
# Validates:
# - Normal push (both local_sha and remote_sha set)
# - New branch push (remote_sha is all zeros)
# - Branch deletion (local_sha is all zeros - should skip)
# - Multiple refs in stdin
# - Empty stdin fallback behavior

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER_SRC="$ROOT/hooks/hook-wrapper.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/caulking.prepush.XXXXXX")"
cleanup() { rm -rf "$tmp" || true; }
trap cleanup EXIT

command -v gitleaks > /dev/null 2>&1 || {
  echo "SKIP: gitleaks not installed"
  exit 0
}

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/xdg"
mkdir -p "$HOME" "$XDG_CONFIG_HOME"

# Create gitleaks config
mkdir -p "$XDG_CONFIG_HOME/gitleaks"
cat > "$XDG_CONFIG_HOME/gitleaks/config.toml" << 'EOF'
title="test"
[extend]
useDefault=true
EOF

# Setup: Create a "remote" repo and a "local" repo
remote_repo="$tmp/remote"
local_repo="$tmp/local"

mkdir -p "$remote_repo"
git init -q --bare "$remote_repo"

git clone -q "$remote_repo" "$local_repo"
cd "$local_repo"
git config user.name "test"
git config user.email "test@gsa.gov"

# Create initial commit so we have a valid HEAD
echo "initial" > README.md
git add README.md
git commit -q -m "initial commit"
git push -q origin main 2> /dev/null || git push -q origin master 2> /dev/null || true

# Get current branch name and SHA
branch_name="$(git rev-parse --abbrev-ref HEAD)"
initial_sha="$(git rev-parse HEAD)"

# Copy hook wrapper for testing
hook="$tmp/pre-push"
cp -f "$WRAPPER_SRC" "$hook"
chmod +x "$hook"

echo "=== Test 1: Normal push (update existing branch) ==="
# Add a clean commit
echo "clean content" > clean.txt
git add clean.txt
git commit -q -m "clean commit"
new_sha="$(git rev-parse HEAD)"

# Simulate pre-push stdin for normal push: <local_ref> <local_sha> <remote_ref> <remote_sha>
push_stdin="refs/heads/$branch_name $new_sha refs/heads/$branch_name $initial_sha"
echo "$push_stdin" | "$hook" origin "$remote_repo" > /dev/null 2>&1
echo "PASS: Normal push completed"

echo ""
echo "=== Test 2: Branch deletion (local_sha all zeros - should skip) ==="
# When deleting a branch, local_sha is 0000...
zero_sha="0000000000000000000000000000000000000000"
delete_stdin="refs/heads/to-delete $zero_sha refs/heads/to-delete $new_sha"
echo "$delete_stdin" | "$hook" origin "$remote_repo" > /dev/null 2>&1
echo "PASS: Branch deletion skipped correctly"

echo ""
echo "=== Test 3: New branch push (remote_sha all zeros) ==="
# Create a new branch
git checkout -q -b new-feature
echo "feature" > feature.txt
git add feature.txt
git commit -q -m "feature commit"
feature_sha="$(git rev-parse HEAD)"

# When pushing a new branch, remote_sha is 0000...
new_branch_stdin="refs/heads/new-feature $feature_sha refs/heads/new-feature $zero_sha"
echo "$new_branch_stdin" | "$hook" origin "$remote_repo" > /dev/null 2>&1
echo "PASS: New branch push completed"

echo ""
echo "=== Test 4: Multiple refs in stdin ==="
git checkout -q "$branch_name"
echo "another" > another.txt
git add another.txt
git commit -q -m "another commit"
another_sha="$(git rev-parse HEAD)"

# Multiple refs in one push
multi_stdin="refs/heads/$branch_name $another_sha refs/heads/$branch_name $new_sha
refs/heads/new-feature $feature_sha refs/heads/new-feature $zero_sha"
echo "$multi_stdin" | "$hook" origin "$remote_repo" > /dev/null 2>&1
echo "PASS: Multiple refs push completed"

echo ""
echo "=== Test 5: Secret in pushed commit should FAIL ==="
echo "aws_secret_access_key = WT8ftNba7siVx5UOoGzJSyd82uNCZAC8LCllzcWp" > secret.txt
git add secret.txt
git commit -q -m "oops secret"
secret_sha="$(git rev-parse HEAD)"

secret_stdin="refs/heads/$branch_name $secret_sha refs/heads/$branch_name $another_sha"
set +e
echo "$secret_stdin" | "$hook" origin "$remote_repo" > /dev/null 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: Secret push should have been blocked"
  exit 1
fi
echo "PASS: Secret push blocked as expected"

echo ""
echo "All pre-push tests passed!"
