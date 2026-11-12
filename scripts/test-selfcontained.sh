#!/usr/bin/env bash
# test-selfcontained.sh — regression guard for the self-installing hooks (#36).
#
# Proves, in a CLEAN golang container with NOTHING pre-installed, that the
# language: golang self-contained hooks bootstrap their tool and run, and that
# the upstream gitleaks hook (ADR-0009 / Option C) both passes clean AND fails on
# a planted secret (fail-closed). This is the permanent guard against the class
# of bug where a language: golang repo:local hook silently breaks in a sandbox
# (missing repo-root go.mod, wrong entry shape, Go-version floor, etc).
#
# Hooks exercised: gofmt-selfcontained, go-vet-selfcontained, gosec-selfcontained,
# govulncheck-selfcontained (from THIS repo) + upstream gitleaks.
#
# Zscaler note: on a host behind Zscaler TLS interception, external HTTPS
# (go proxy, vuln.go.dev, github) fails cert verification inside the container.
# If a Zscaler root CA is found on the host we mount+trust it so the test works
# locally; in CI (clean egress) no CA is needed and none is injected. govulncheck
# needs egress to vuln.go.dev, so it is INCLUDED in the gate (the CA handling
# makes it reliable behind Zscaler and it Just Works in clean CI).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GO_IMAGE="${SELFCONTAINED_GO_IMAGE:-golang:1.25-bookworm}"
GITLEAKS_REV="${SELFCONTAINED_GITLEAKS_REV:-v8.30.1}"

# --- Locate a Zscaler (or other corporate) root CA on the host, if present. ---
# macOS: export from the System keychain. Linux: check the usual bundle dir.
ca_mount_args=()
ca_pem="$(mktemp)"
trap 'rm -f "$ca_pem"' EXIT
if command -v security > /dev/null 2>&1; then
  security find-certificate -a -c "Zscaler" -p \
    /Library/Keychains/System.keychain > "$ca_pem" 2> /dev/null || true
fi
if [ ! -s "$ca_pem" ]; then
  for f in /usr/local/share/ca-certificates/*scaler* /etc/ssl/certs/*scaler*; do
    if [ -f "$f" ]; then
      cat "$f" >> "$ca_pem" 2> /dev/null || true
    fi
  done
fi
if [ -s "$ca_pem" ] && grep -q "BEGIN CERTIFICATE" "$ca_pem"; then
  echo "test-selfcontained: found a corporate root CA on the host; trusting it in the container."
  ca_mount_args=(-v "$ca_pem:/corp-ca.pem:ro")
else
  echo "test-selfcontained: no corporate CA found (clean egress assumed, e.g. CI)."
fi

# --- The in-container test body. ---
runner="$(mktemp)"
trap 'rm -f "$ca_pem" "$runner"' EXIT
cat > "$runner" << 'INNER'
set -euo pipefail
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq git python3-pip ca-certificates >/dev/null 2>&1
if [ -f /corp-ca.pem ]; then
	cp /corp-ca.pem /usr/local/share/ca-certificates/corp.crt
	update-ca-certificates >/dev/null 2>&1
	export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
fi

# Use the mounted template as a local hook repo (needs a commit for try-repo).
cp -r /work /repo && cd /repo && rm -rf .git
git init -q . && git config user.email ci@gsa.gov && git config user.name ci
git add -A && git commit -q -m "test snapshot"
sha="$(git rev-parse HEAD)"

# A throwaway consumer repo with a clean, buildable Go module.
cd /tmp && rm -rf proj && mkdir proj && cd proj
git init -q . && git config user.email ci@gsa.gov && git config user.name ci
printf 'module example.com/p\ngo 1.21\n' >go.mod
printf 'package main\n\nfunc main() {}\n' >main.go
printf 'clean\n' >notes.txt
cat >.pre-commit-config.yaml <<CFG
repos:
  - repo: /repo
    rev: ${sha}
    hooks:
      - id: gofmt-selfcontained
      - id: go-vet-selfcontained
      - id: gosec-selfcontained
      - id: govulncheck-selfcontained
  - repo: https://github.com/gitleaks/gitleaks
    rev: __GITLEAKS_REV__
    hooks:
      - id: gitleaks
CFG
git add -A
pip install --break-system-packages --quiet pre-commit

echo "== self-contained hooks: clean run (expect all pass) =="
pre-commit run --all-files
echo "== PASS: all self-contained hooks green on a clean tree =="

echo "== fail-closed check: plant a secret, gitleaks MUST fail =="
# Assemble a GitHub-PAT-shaped token at RUNTIME from fragments so NO literal
# secret-shaped string is committed to this repo (that would trip gitleaks on
# THIS repo). gitleaks' github-pat rule matches 'ghp_' + 36 alphanumerics.
fake_tok="ghp_$(printf 'abcdefghij0123456789abcdefghij012345')"
printf 'tok="%s"\n' "$fake_tok" >leak.txt
git add leak.txt
if pre-commit run gitleaks --all-files >/dev/null 2>&1; then
	echo "FAIL: gitleaks did NOT flag a planted secret (fail-open!)" >&2
	exit 1
fi
echo "== PASS: gitleaks flagged the planted secret (fail-closed) =="
INNER
# inject the pinned gitleaks rev
sed -i.bak "s|__GITLEAKS_REV__|${GITLEAKS_REV}|" "$runner" && rm -f "$runner.bak"

echo "test-selfcontained: running in ${GO_IMAGE} (nothing pre-installed)..."
docker run --rm \
  -v "$REPO_ROOT:/work:ro" \
  -v "$runner:/runner.sh:ro" \
  "${ca_mount_args[@]}" \
  "$GO_IMAGE" bash /runner.sh
