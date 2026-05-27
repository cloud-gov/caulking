# Blocked Files Reference

This document describes the files that caulking blocks from being committed to prevent credential leaks and security issues.

## Overview

Caulking prevents two categories of sensitive files:

1. **Content-based detection** (via gitleaks) - Scans file contents for secrets
2. **Filename-based blocking** (built-in denylist) - Blocks high-risk file types regardless of content

## Filename-Based Blocking

The following file types are blocked by filename pattern, even if they contain no secrets.

### Private Keys & Certificates

**Why blocked:** These files commonly contain cryptographic private keys.

| Pattern | Examples | Notes |
|---------|----------|-------|
| `*.pem` | `server.pem`, `cert.pem` | PEM-encoded certificates/keys |
| `*.key` | `private.key`, `ssl.key` | Generic key files |
| `*.der` | `cert.der` | DER-encoded certificates |
| `*.p12` | `keystore.p12` | PKCS#12 keystores |
| `*.pfx` | `cert.pfx` | Personal Information Exchange |
| `*.pkcs8` | `private.pkcs8` | PKCS#8 private keys |
| `*.jks` | `keystore.jks` | Java KeyStore |
| `*.keystore` | `app.keystore` | Android/Java keystores |
| `*.kdbx` | `passwords.kdbx` | KeePass database |
| `*.agekey` | `identity.agekey` | age encryption keys |

**Alternative:** Store keys in a secret manager (AWS Secrets Manager, HashiCorp Vault) and reference at runtime.

### SSH Keys

**Why blocked:** SSH keys grant direct system access.

| Pattern | Examples | Notes |
|---------|----------|-------|
| `id_rsa` | `~/.ssh/id_rsa` | RSA private key |
| `id_dsa` | `~/.ssh/id_dsa` | DSA private key |
| `id_ecdsa` | `~/.ssh/id_ecdsa` | ECDSA private key |
| `id_ed25519` | `~/.ssh/id_ed25519` | Ed25519 private key |
| `ssh_host_*_key` | `ssh_host_rsa_key` | Server host keys |

**Alternative:** Use SSH agent forwarding or deploy keys instead of committing keys.

### Environment & Credential Files

**Why blocked:** These files typically contain API keys, tokens, and passwords.

| Pattern | Examples | Notes |
|---------|----------|-------|
| `.env`, `.env.*` | `.env.local`, `.env.production` | Environment variables |
| `.envrc` | `.envrc` | direnv configuration |
| `.netrc` | `~/.netrc` | HTTP authentication |
| `.git-credentials` | `~/.git-credentials` | Git credential store |

#### Allowed Exceptions

The following patterns are **explicitly allowed** because they are documentation/template files that should not contain real secrets:

| Pattern | Examples | Notes |
|---------|----------|-------|
| `*.example` | `.env.example`, `.env.local.example` | Example configuration templates |
| `*.sample` | `.env.sample` | Sample configuration files |
| `*.template` | `.env.template` | Template files for documentation |

**Best practice:** Use `.env.example` with placeholder values like `YOUR_API_KEY_HERE`, keep actual `.env` gitignored.

**Alternative:** Use `.env.example` with placeholders, keep actual `.env` gitignored.

### Cloud Provider Credentials

**Why blocked:** Cloud credentials grant access to production infrastructure.

| Pattern | Examples | Notes |
|---------|----------|-------|
| `.aws/credentials` | `~/.aws/credentials` | AWS access keys |
| `.aws/config` | `~/.aws/config` | AWS configuration (may contain sensitive data) |
| `.aws-vault/keys/*` | `~/.aws-vault/keys/default` | aws-vault encrypted credentials |
| `.cf/config.json` | `~/.cf/config.json` | Cloud Foundry CLI tokens |
| `.flyrc` | `~/.flyrc` | Concourse CI tokens |
| `.docker/config.json` | `~/.docker/config.json` | Docker registry auth |

**Alternative:** Use IAM roles, instance profiles, or CI/CD-specific credential injection.

### Kubernetes Configuration

**Why blocked:** Kubeconfig files contain cluster certificates and tokens.

| Pattern | Examples | Notes |
|---------|----------|-------|
| `.kube/config` | `~/.kube/config` | kubectl configuration |
| `kubeconfig`, `kubeconfig.*` | `kubeconfig.prod` | Alternative kubeconfig names |

**Alternative:** Use RBAC service accounts, OIDC authentication, or cluster-specific contexts.

### Terraform State & Credentials

**Why blocked:** Terraform state can contain secrets, credentials files expose infrastructure access.

| Pattern | Examples | Notes |
|---------|----------|-------|
| `*.tfstate` | `terraform.tfstate` | Terraform state (may contain secrets) |
| `*.tfstate.backup` | `terraform.tfstate.backup` | State backup |
| `terraform.tfstate.d/*` | Workspaces directory | Workspace states |
| `.terraform/*` | `.terraform/plugins/` | Provider cache (may contain creds) |
| `.terraformrc` | `~/.terraformrc` | Terraform CLI config with tokens |
| `credentials.tfrc.json` | `credentials.tfrc.json` | Terraform Cloud tokens |

**Alternative:** Use remote state (S3, Terraform Cloud) with encryption. Never commit state files.

### System Credential Files

**Why blocked:** These files contain system passwords and authentication data.

| Pattern | Examples | Notes |
|---------|----------|-------|
| `shadow` | `/etc/shadow` | Linux password hashes |
| `passwd` | `/etc/passwd` | User account info |
| `group` | `/etc/group` | Group definitions |
| `gshadow` | `/etc/gshadow` | Secure group info |

**Alternative:** These should never be in git. Use configuration management (Ansible, Chef, Puppet) instead.

### Package Manager Credentials

**Why blocked:** These files can contain registry authentication tokens.

| Pattern | Examples | Validation |
|---------|----------|------------|
| `.pypirc` | `~/.pypirc` | **Blocked unconditionally** - Python package index credentials |
| `.npmrc` | `.npmrc`, `~/.npmrc` | **Content-validated** - See [.npmrc Handling](#npmrc-handling) below |

### Miscellaneous

| Pattern | Examples | Notes |
|---------|----------|-------|
| `.vault-token` | `~/.vault-token` | HashiCorp Vault token |

---

## .npmrc Handling

**Special case:** `.npmrc` files are **content-validated** rather than blanket-blocked.

### Why .npmrc Is Different

Project-level `.npmrc` files often contain **security controls** that SHOULD be committed:

```ini
# SAFE - Security best practices
ignore-scripts=true
audit=true
fund=false
```

User-level `.npmrc` files contain **auth tokens** that should NEVER be committed:

```ini
# UNSAFE - Contains credentials
//registry.npmjs.org/:_authToken=npm_abc123...
```

### Validation Rules

Caulking uses **content-based validation** for `.npmrc` files:

#### ✅ Allowed (Safe Configuration)

```ini
# Project-level security settings
ignore-scripts=true
audit=true
registry=https://registry.npmjs.org/
@myorg:registry=https://npm.myorg.com/
```

#### ❌ Blocked (Credentials Detected)

Caulking blocks `.npmrc` files containing:

- `_authToken=...` - npm authentication token
- `_auth=...` - base64-encoded username:password
- `_password=...` - plaintext password
- `:_authToken=...` - scoped registry token
- `//registry.example.com/:_authToken=...` - registry-specific token

#### ⚠️ Warning (Missing Security Controls)

If `.npmrc` is missing `ignore-scripts=true`, caulking warns but allows the commit:

```
WARNING: .npmrc missing 'ignore-scripts=true' (recommended security control)
Add this line to .npmrc to prevent arbitrary script execution:
  ignore-scripts=true
```

### Recommended Pattern

**Project `.npmrc` (committed to git):**
```ini
# Security controls
ignore-scripts=true
audit=true

# Registry configuration (no tokens!)
@myorg:registry=https://npm.myorg.com/
```

**User `.npmrc` (`~/.npmrc`, gitignored):**
```ini
# Auth tokens (NEVER commit these)
//registry.npmjs.org/:_authToken=${NPM_TOKEN}
//npm.myorg.com/:_authToken=${ORG_NPM_TOKEN}
```

### Testing Your .npmrc

To verify your `.npmrc` file will be allowed:

```bash
# Check for credentials
grep -E '(_authToken|_auth|_password)' .npmrc

# If this returns results, remove them before committing
```

---

## Content-Based Detection (Gitleaks)

In addition to filename-based blocking, caulking runs **gitleaks** on every commit to detect secrets in file contents.

Gitleaks detects 100+ secret patterns including:

- API keys (AWS, Google Cloud, Azure, etc.)
- Authentication tokens (GitHub, GitLab, Slack, etc.)
- Database connection strings
- Private keys embedded in code
- Generic high-entropy strings

**This runs on ALL files**, not just the ones listed above.

### Example Detection

Even if you name a file innocuously, gitleaks will detect secrets:

```bash
# This will be caught even though it's not on the denylist
$ cat config.txt
aws_access_key_id = AKIAIOSFODNN7EXAMPLE

$ git add config.txt
$ git commit -m "Add config"
# ❌ BLOCKED by gitleaks
```

---

## Emergency Bypass

### Bypassing Filename Checks

**You cannot bypass the forbidden-files check.** If you need to commit a `.pem` file, you are doing something wrong.

### Bypassing Gitleaks (Use Sparingly)

For known false positives, use repository allowlists:

```toml
# .gitleaks.repo.toml
title = "Repo allowlist"

[extend]
useDefault = true

[allowlist]
description = "Known-safe patterns"

regexes = [
  "FAKE_TEST_SECRET_12345",  # Test fixture
]

paths = [
  "fixtures/test-data.json",  # Test data directory
]
```

**One-time break-glass:**

```bash
SKIP=gitleaks git commit -m "emergency commit"
```

Document why you bypassed and create a follow-up task.

---

## Testing Blocked Files

To test if a file will be blocked:

```bash
# Create test file
echo "test content" > test.pem

# Try to commit
git add test.pem
git commit -m "test"

# Expected result:
# ERROR: forbidden file staged: test.pem
# Caulking blocked a forbidden file from being committed.
```

---

## See Also

- [Caulking README](../README.md) - Installation and usage
- [Gitleaks Rules](https://github.com/gitleaks/gitleaks#rules) - Full list of detection patterns
- [npm .npmrc documentation](https://docs.npmjs.com/cli/v10/configuring-npm/npmrc) - Official npm configuration guide
- [OWASP Secrets Management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html) - Best practices
