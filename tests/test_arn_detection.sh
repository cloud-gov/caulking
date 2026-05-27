#!/usr/bin/env bash
# test_arn_detection.sh
#
# Test AWS ARN detection - warns on hardcoded account IDs
# Issue: https://github.com/cloud-gov/caulking/issues/111

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER_SRC="$ROOT/hooks/hook-wrapper.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/caulking.arn.XXXXXX")"
cleanup() { rm -rf "$tmp" || true; }
trap cleanup EXIT

command -v gitleaks > /dev/null 2>&1 || {
  echo "SKIP: gitleaks not installed"
  exit 0
}

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/xdg"
mkdir -p "$HOME" "$XDG_CONFIG_HOME"

repo="$tmp/repo"
mkdir -p "$repo"
cd "$repo"
git init -q
git config user.name "test"
git config user.email "test@gsa.gov"

# Create gitleaks config with ARN detection rule
mkdir -p "$XDG_CONFIG_HOME/gitleaks"
cat > "$XDG_CONFIG_HOME/gitleaks/config.toml" << 'EOF'
title = "ARN Detection Test Config"

[extend]
useDefault = true

[[rules]]
id = "aws-arn-account-id"
description = "AWS ARN with hardcoded account ID"
regex = '''arn:aws(-us-gov|-cn)?:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:[a-zA-Z0-9/_=+.@:-]+'''
keywords = ["arn:aws"]

  [rules.allowlist]
  regexes = [
    '''\$\{[^}]*ACCOUNT[^}]*\}''',
    '''\$\{[^}]*AWS[^}]*\}''',
    '''\$ACCOUNT''',
    '''\$AWS_ACCOUNT''',
    '''123456789012''',
    '''111122223333''',
    '''444455556666''',
    '''999999999999''',
    ''':\*:''',
  ]
EOF

hook="$tmp/pre-commit"
cp -f "$WRAPPER_SRC" "$hook"
chmod +x "$hook"

echo "=== Test 1: Hardcoded IAM ARN should be BLOCKED ==="
cat > arn_test.txt << 'CONTENT'
# Production IAM role
arn:aws:iam::987654321098:role/prod-admin-role
CONTENT
git add arn_test.txt

"$hook" > /dev/null 2>&1 && rc=0 || rc=$?

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: Hardcoded IAM ARN should have been blocked"
  exit 1
fi
echo "PASS: Hardcoded IAM ARN blocked"

git reset -q HEAD -- arn_test.txt 2> /dev/null || true
rm -f arn_test.txt

echo ""
echo "=== Test 2: GovCloud ARN should be BLOCKED ==="
cat > arn_test.txt << 'CONTENT'
# GovCloud resource
arn:aws-us-gov:iam::876543210987:user/gov-admin
CONTENT
git add arn_test.txt

"$hook" > /dev/null 2>&1 && rc=0 || rc=$?

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: GovCloud ARN should have been blocked"
  exit 1
fi
echo "PASS: GovCloud ARN blocked"

git reset -q HEAD -- arn_test.txt 2> /dev/null || true
rm -f arn_test.txt

echo ""
echo "=== Test 3: China region ARN should be BLOCKED ==="
cat > arn_test.txt << 'CONTENT'
# China region resource
arn:aws-cn:iam::765432109876:role/cn-role
CONTENT
git add arn_test.txt

"$hook" > /dev/null 2>&1 && rc=0 || rc=$?

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: China ARN should have been blocked"
  exit 1
fi
echo "PASS: China ARN blocked"

git reset -q HEAD -- arn_test.txt 2> /dev/null || true
rm -f arn_test.txt

echo ""
echo "=== Test 4: Variable interpolation ARN should be ALLOWED ==="
cat > arn_test.txt << 'CONTENT'
# Safe - uses variable interpolation
arn:aws:iam::${ACCOUNT_ID}:role/service-role
arn:aws:lambda:us-east-1:${AWS_ACCOUNT_ID}:function:processor
CONTENT
git add arn_test.txt

"$hook" > /dev/null 2>&1 && rc=0 || rc=$?

if [[ "$rc" -ne 0 ]]; then
  echo "FAIL: Variable interpolation ARN should have been allowed"
  exit 1
fi
echo "PASS: Variable interpolation ARN allowed"

git reset -q HEAD -- arn_test.txt 2> /dev/null || true
rm -f arn_test.txt

echo ""
echo "=== Test 5: AWS documentation example account IDs should be ALLOWED ==="
cat > arn_test.txt << 'CONTENT'
# Documentation examples (AWS uses these in docs)
arn:aws:iam::123456789012:user/ExampleUser
arn:aws:iam::111122223333:role/ExampleRole
CONTENT
git add arn_test.txt

"$hook" > /dev/null 2>&1 && rc=0 || rc=$?

if [[ "$rc" -ne 0 ]]; then
  echo "FAIL: Documentation example ARNs should have been allowed"
  exit 1
fi
echo "PASS: Documentation example ARNs allowed"

git reset -q HEAD -- arn_test.txt 2> /dev/null || true
rm -f arn_test.txt

echo ""
echo "=== Test 6: S3 ARN (no account ID) should be ALLOWED ==="
cat > arn_test.txt << 'CONTENT'
# S3 bucket ARNs don't have account IDs
arn:aws:s3:::my-production-bucket
arn:aws:s3:::my-bucket/*
CONTENT
git add arn_test.txt

"$hook" > /dev/null 2>&1 && rc=0 || rc=$?

if [[ "$rc" -ne 0 ]]; then
  echo "FAIL: S3 ARN should have been allowed"
  exit 1
fi
echo "PASS: S3 ARN allowed"

git reset -q HEAD -- arn_test.txt 2> /dev/null || true
rm -f arn_test.txt

echo ""
echo "=== Test 7: Wildcard account ARN should be ALLOWED ==="
cat > arn_test.txt << 'CONTENT'
# IAM policy with wildcard
arn:aws:iam::*:role/ServiceRole
CONTENT
git add arn_test.txt

"$hook" > /dev/null 2>&1 && rc=0 || rc=$?

if [[ "$rc" -ne 0 ]]; then
  echo "FAIL: Wildcard ARN should have been allowed"
  exit 1
fi
echo "PASS: Wildcard ARN allowed"

git reset -q HEAD -- arn_test.txt 2> /dev/null || true
rm -f arn_test.txt

echo ""
echo "=== Test 8: Multiple services with hardcoded IDs should be BLOCKED ==="
cat > arn_test.txt << 'CONTENT'
# Multiple sensitive ARNs
arn:aws:lambda:us-east-1:555566667777:function:process-secrets
arn:aws:secretsmanager:us-west-2:555566667777:secret:api-key
arn:aws:ec2:us-east-1:555566667777:instance/i-abc123
CONTENT
git add arn_test.txt

"$hook" > /dev/null 2>&1 && rc=0 || rc=$?

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: Multiple hardcoded ARNs should have been blocked"
  exit 1
fi
echo "PASS: Multiple hardcoded ARNs blocked"

echo ""
echo "All ARN detection tests passed!"
