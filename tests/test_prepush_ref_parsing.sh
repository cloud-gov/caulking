#!/usr/bin/env bash
# Test pre-push hook stdin ref parsing and gitleaks invocation
set -euo pipefail

# shellcheck source=lib/test-helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/test-helpers.sh"

# Use pre-push hook instead of pre-commit
full_test_setup "pre-push"

# Setup: Create a "remote" repo and work in "local" repo
remote_repo="$TEST_TMP/remote"
local_repo="$TEST_TMP/local"

mkdir -p "$remote_repo"
git init -q --bare "$remote_repo"

git clone -q "$remote_repo" "$local_repo"
cd "$local_repo"
git config user.name "test"
git config user.email "test@gsa.gov"

# Create initial commit
echo "initial" > README.md
git add README.md
git commit -q -m "initial commit"
git push -q origin main 2> /dev/null || git push -q origin master 2> /dev/null || true

branch_name="$(git rev-parse --abbrev-ref HEAD)"
initial_sha="$(git rev-parse HEAD)"

echo "=== Test 1: Normal push (update existing branch) ==="
echo "clean content" > clean.txt
git add clean.txt
git commit -q -m "clean commit"
new_sha="$(git rev-parse HEAD)"

push_stdin="refs/heads/$branch_name $new_sha refs/heads/$branch_name $initial_sha"
echo "$push_stdin" | "$TEST_HOOK" origin "$remote_repo" > /dev/null 2>&1
echo "PASS: Normal push completed"

echo ""
echo "=== Test 2: Branch deletion (local_sha all zeros - should skip) ==="
zero_sha="0000000000000000000000000000000000000000"
delete_stdin="refs/heads/to-delete $zero_sha refs/heads/to-delete $new_sha"
echo "$delete_stdin" | "$TEST_HOOK" origin "$remote_repo" > /dev/null 2>&1
echo "PASS: Branch deletion skipped correctly"

echo ""
echo "=== Test 3: New branch push (remote_sha all zeros) ==="
git checkout -q -b new-feature
echo "feature" > feature.txt
git add feature.txt
git commit -q -m "feature commit"
feature_sha="$(git rev-parse HEAD)"

new_branch_stdin="refs/heads/new-feature $feature_sha refs/heads/new-feature $zero_sha"
echo "$new_branch_stdin" | "$TEST_HOOK" origin "$remote_repo" > /dev/null 2>&1
echo "PASS: New branch push completed"

echo ""
echo "=== Test 4: Multiple refs in stdin ==="
git checkout -q "$branch_name"
echo "another" > another.txt
git add another.txt
git commit -q -m "another commit"
another_sha="$(git rev-parse HEAD)"

multi_stdin="refs/heads/$branch_name $another_sha refs/heads/$branch_name $new_sha
refs/heads/new-feature $feature_sha refs/heads/new-feature $zero_sha"
echo "$multi_stdin" | "$TEST_HOOK" origin "$remote_repo" > /dev/null 2>&1
echo "PASS: Multiple refs push completed"

echo ""
echo "=== Test 5: Secret in pushed commit should FAIL ==="
echo "aws_secret_access_key = WT8ftNba7siVx5UOoGzJSyd82uNCZAC8LCllzcWp" > secret.txt
git add secret.txt
git commit -q -m "oops secret"
secret_sha="$(git rev-parse HEAD)"

secret_stdin="refs/heads/$branch_name $secret_sha refs/heads/$branch_name $another_sha"
echo "$secret_stdin" | "$TEST_HOOK" origin "$remote_repo" > /dev/null 2>&1 && rc=0 || rc=$?

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: Secret push should have been blocked"
  exit 1
fi
echo "PASS: Secret push blocked as expected"

echo ""
echo "All pre-push tests passed!"
