# Supply Chain Security Monitoring

This document defines the monitoring and review process for tools in the `cloud-gov/caulking` workstation toolchain (`brewfiles/*.Brewfile`) and reusable pre-commit hook catalog (`.pre-commit-hooks.yaml`).

> **Scope:** This monitoring covers tools for local development on macOS workstations (provisioned via selective `brewfiles/<profile>.Brewfile` bundles and `caulking bootstrap`) and reusable hooks. CI/CD tool monitoring is managed separately by each team's pipeline configuration.

**NIST Control:** SA-12 (Supply Chain Protection)  
**Review Frequency:** Quarterly  
**Last Updated:** 2026-11-09

---

## Tool Inventory

All tools have been security-assessed. See [ADR-0004](adr/ADR-0004-supply-chain-security.md) and [ADR-0006](adr/ADR-0006-language-security-tools.md) for details.

### Core & Baseline Tools (`brewfiles/baseline.Brewfile`)

| Tool | Version Floor | Maintainer | Risk | Repository | Review |
|------|---------------|------------|------|------------|--------|
| gitleaks | 8.18+ | Zachary Rice / Community | LOW | [gitleaks/gitleaks](https://github.com/gitleaks/gitleaks) | Quarterly |
| pre-commit | 3.2+ (4.x) | Anthony Sottile | LOW | [pre-commit/pre-commit](https://github.com/pre-commit/pre-commit) | Quarterly |
| prek | 0.1+ | j178 | LOW | [j178/prek](https://github.com/j178/prek) | Quarterly |
| jq | 1.6+ | jq maintainers | LOW | [jqlang/jq](https://github.com/jqlang/jq) | Quarterly |
| pyyaml | 6.0+ | YAML maintainers | LOW | [yaml/pyyaml](https://github.com/yaml/pyyaml) | Quarterly |

### Language & Linter Bundles (`brewfiles/<profile>.Brewfile`)

| Tool | Bundle | Version | Maintainer | Risk | Repository | Review |
|------|--------|---------|------------|------|------------|--------|
| shellcheck | `shell` | 0.10+ | Vidar Holen | LOW | [koalaman/shellcheck](https://github.com/koalaman/shellcheck) | Quarterly |
| shfmt | `shell` | 3.8+ | Daniel Martí | LOW | [mvdan/sh](https://github.com/mvdan/sh) | Quarterly |
| hadolint | `container` | 2.12+ | Community | LOW | [hadolint/hadolint](https://github.com/hadolint/hadolint) | Quarterly |
| ruff | `python` | 0.6+ | Astral/OpenAI | LOW | [astral-sh/ruff](https://github.com/astral-sh/ruff) | Quarterly |
| mypy | `python` | 1.10+ | Python/PSF | LOW | [python/mypy](https://github.com/python/mypy) | Quarterly |
| bandit | `python` | 1.7+ | PyCQA | LOW | [PyCQA/bandit](https://github.com/PyCQA/bandit) | Quarterly |
| pip-audit | `python` | 2.7+ | PyPA | LOW | [pypa/pip-audit](https://github.com/pypa/pip-audit) | Quarterly |
| golangci-lint | `go` | 1.60+ / 2.x | Community | LOW | [golangci/golangci-lint](https://github.com/golangci/golangci-lint) | Quarterly |
| gosec | `go` | 2.20+ | securego | LOW | [securego/gosec](https://github.com/securego/gosec) | Quarterly |
| govulncheck | `go` | 1.1+ | Go Team | LOW | [golang/vuln](https://github.com/golang/vuln) | Quarterly |
| tflint | `opentofu` / `terraform` | 0.50+ | terraform-linters | LOW-MED | [terraform-linters/tflint](https://github.com/terraform-linters/tflint) | Quarterly |
| git-cliff | optional | 2.x | orhun | LOW | [orhun/git-cliff](https://github.com/orhun/git-cliff) | Quarterly |

### IaC Tools (Teams Choose One: `opentofu` or `terraform` bundle)

| Tool | Bundle | Version | Maintainer | Risk | Repository | Review |
|------|--------|---------|------------|------|------------|--------|
| opentofu | `opentofu` | 1.7+ | Linux Foundation | LOW | [opentofu/opentofu](https://github.com/opentofu/opentofu) | Quarterly |
| terraform | `terraform` | 1.5+ | HashiCorp/IBM | MEDIUM | [hashicorp/terraform](https://github.com/hashicorp/terraform) | Quarterly |

### Universal Security Scanners (`brewfiles/security.Brewfile`)

| Tool | Version | Maintainer | Risk | Repository | Review |
|------|---------|------------|------|------------|--------|
| semgrep | 1.80+ | Semgrep Inc. | LOW | [semgrep/semgrep](https://github.com/semgrep/semgrep) | Quarterly |
| osv-scanner | 1.8+ | Google OSS Security | LOW | [google/osv-scanner](https://github.com/google/osv-scanner) | Quarterly |
| syft | 1.0+ | Anchore Inc. | LOW | [anchore/syft](https://github.com/anchore/syft) | Quarterly |
| grype | 0.79+ | Anchore Inc. | LOW | [anchore/grype](https://github.com/anchore/grype) | Quarterly |

### JavaScript/TypeScript Tools (`brewfiles/javascript.Brewfile` + project `devDependencies`)

| Tool | Version | Maintainer | Risk | Repository | Review |
|------|---------|------------|------|------------|--------|
| node | 18+ | OpenJS Foundation | LOW | [nodejs/node](https://github.com/nodejs/node) | Quarterly |
| eslint | 9.x | OpenJS Foundation | LOW | [eslint/eslint](https://github.com/eslint/eslint) | Quarterly |
| prettier | 3.x | Community | LOW | [prettier/prettier](https://github.com/prettier/prettier) | Quarterly |
| typescript | 5.x | Microsoft | LOW | [microsoft/TypeScript](https://github.com/microsoft/TypeScript) | Quarterly |
| biome | 1.7+ / 2.x | Community | LOW-MED | [biomejs/biome](https://github.com/biomejs/biome) | Quarterly |

### Excluded Tools

| Tool | Owner | Reason | Alternative |
|------|-------|--------|-------------|
| trivy | Aqua Security | Supply chain concerns | grype (Anchore) |
| tfsec | Aqua Security | Supply chain concerns | semgrep |
| tracee | Aqua Security | Supply chain concerns | - |

---

## Single-Maintainer Risk Tools

These tools have elevated continuity risk due to single-maintainer governance. They are approved with enhanced monitoring.

### shellcheck (Vidar Holen)

| Attribute | Value |
|-----------|-------|
| Repository | [koalaman/shellcheck](https://github.com/koalaman/shellcheck) |
| Stars | 39,500+ |
| Active Since | 2012 (13+ years) |
| Last Release | Check quarterly |
| Backup Alternative | bashate, sh -n (POSIX) |

**Monitoring triggers:**
- No commits for 6+ months
- Maintainer account changes
- Ownership transfer

### shfmt (Daniel Martí)

| Attribute | Value |
|-----------|-------|
| Repository | [mvdan/sh](https://github.com/mvdan/sh) |
| Stars | 8,800+ |
| Active Since | 2016 |
| Last Release | Check quarterly |
| Backup Alternative | beautysh, shell-format (VS Code) |

**Monitoring triggers:**
- No commits for 6+ months
- Maintainer account changes

### git-cliff (orhun)

| Attribute | Value |
|-----------|-------|
| Repository | [orhun/git-cliff](https://github.com/orhun/git-cliff) |
| Stars | 11,900+ |
| Active Since | 2021 |
| Last Release | Check quarterly |
| Backup Alternative | release-please, conventional-changelog, standard-version |

**Monitoring triggers:**
- No commits for 6+ months
- Maintainer account changes
- Project archive/deprecation

---

## Quarterly Review Checklist

Use this checklist each quarter to verify tool health.

### Pre-Review Setup

- [ ] Check current date: Q__ 20__
- [ ] Assign reviewer: ________________
- [ ] Create tracking issue in GitHub

### For Each Tool

- [ ] **Activity Check**: Verify commits within last 6 months
- [ ] **Release Check**: Review releases since last review
- [ ] **CVE Check**: Search NVD/OSV for new vulnerabilities
- [ ] **Advisory Check**: Review GitHub Security Advisories
- [ ] **Signature Check**: Verify releases still signed/checksummed
- [ ] **License Check**: No license changes
- [ ] **Maintainer Check**: No ownership transfers

### Documentation Updates

- [ ] Update [ADR-0004](adr/ADR-0004-supply-chain-security.md) if any tool status changed
- [ ] Update minimum supported versions in `lib/profiles.sh` if security advisories require raising floors
- [ ] Update this `MONITORING.md` with new versions
- [ ] Close tracking issue with summary

### Escalation Triggers

Escalate to security team if:
- [ ] New HIGH or CRITICAL CVE discovered
- [ ] Maintainer account compromised
- [ ] Supply chain attack detected
- [ ] License changed to incompatible terms
- [ ] Project archived or abandoned

---

## Monitoring Automation

### GitHub Watch Setup

For each repository, enable "Releases only" notifications:

1. Go to repository (e.g., https://github.com/koalaman/shellcheck)
2. Click "Watch" dropdown
3. Select "Custom" → check "Releases"
4. Save

### Dependabot Configuration

Add to `.github/dependabot.yml` (if using GitHub for monitoring):

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10

  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
```

### OSV Scanner Integration

Run quarterly or in CI:

```bash
# Install osv-scanner (or via caulking bootstrap --profile security)
brew bundle --file=brewfiles/security.Brewfile --no-upgrade

# Scan repository dependencies
osv-scanner -r .
```

---

## Review Schedule

| Quarter | Review Period | Due Date | Reviewer |
|---------|---------------|----------|----------|
| Q1 2026 | Jan 1 - Mar 31 | Apr 7, 2026 | TBD |
| Q2 2026 | Apr 1 - Jun 30 | Jul 7, 2026 | TBD |
| Q3 2026 | Jul 1 - Sep 30 | Oct 7, 2026 | TBD |
| Q4 2026 | Oct 1 - Dec 31 | Jan 7, 2027 | TBD |

### Review Process

1. **Week 1 of new quarter**: Create GitHub issue for quarterly review
2. **Week 1-2**: Run through checklist for all tools
3. **Week 2**: Document findings, update ADRs and version floors
4. **Week 2**: Close issue with summary

---

## References

- [NIST SP 800-53 SA-12: Supply Chain Protection](https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final)
- [ADR-0002: Consolidation of Pre-Commit Templates and Selective Brewfile Bundles](adr/ADR-0002-template-consolidation-and-brewfile-bundles.md)
- [ADR-0004: Supply Chain Security Tool Selection](adr/ADR-0004-supply-chain-security.md)
- [ADR-0006: Language-Specific Security Tool Selection](adr/ADR-0006-language-security-tools.md)
- [OpenSSF Scorecard](https://securityscorecards.dev/)
- [OSV (Open Source Vulnerabilities)](https://osv.dev/)
- [GitHub Security Advisories](https://github.com/advisories)
