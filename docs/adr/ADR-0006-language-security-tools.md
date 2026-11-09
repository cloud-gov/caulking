# ADR-0006: Language-Specific Security Tool Selection

**Status:** Accepted
**Date:** 2026-05-19
**Deciders:** Cloud.gov Platform Team
**Provenance:** Originally recorded as ADR-0004 in cloud-gov/pre-commit-templates prior to repository consolidation into cloud-gov/caulking ([ADR-0002](ADR-0002-template-consolidation-and-brewfile-bundles.md)).

## Context

[ADR-0004](ADR-0004-supply-chain-security.md) established supply chain security criteria and excluded Aqua Security tools. This ADR documents the selection of language-specific SAST (Static Application Security Testing) and SCA (Software Composition Analysis) tools for each supported language ecosystem.

### Requirements

Per NIST SP 800-53 and SSDF:
- **SA-11(1)**: Static code analysis required
- **RA-5**: Vulnerability scanning required
- **PW.7**: Review and/or analyze human-readable code (SSDF)
- **PW.4**: Verify third-party components are free of known vulnerabilities (SSDF)
- **RV.1**: Identify and confirm vulnerabilities on an ongoing basis (SSDF)

### Selection Criteria

1. **Open source** with permissive license (Apache-2.0, MIT, BSD, MPL-2.0)
2. **Trusted maintainer** (foundation-backed, major vendor, or established community)
3. **Active development** (commits within 90 days)
4. **No Aqua Security affiliation** (per [ADR-0004](ADR-0004-supply-chain-security.md))
5. **CWE mapping** preferred for SAST tools
6. **OSV/NVD integration** preferred for SCA tools

## Decision

### Universal Tools (All Languages)

| Category | Tool | Maintainer | License | Rationale |
|----------|------|------------|---------|-----------|
| SAST | semgrep | Semgrep Inc. | LGPL-2.1 | Cross-file dataflow, 2000+ rules, CWE mapping |
| SCA | osv-scanner | Google OSS Security | Apache-2.0 | OSV database, supports all lockfiles |
| SBOM | syft | Anchore Inc. | Apache-2.0 | CycloneDX/SPDX output, broad format support |

### Go

| Category | Tool | Maintainer | License | Rationale |
|----------|------|------------|---------|-----------|
| SAST | gosec | securego | Apache-2.0 | Go-specific rules, CWE mapping, AST-based |
| SCA | govulncheck | Go Team | BSD-3-Clause | Official tool, call-graph analysis, Go vuln DB |

**Alternatives considered:**
- staticcheck: Excellent linter but not security-focused
- nancy (Sonatype): Good but less official than govulncheck

### Python

| Category | Tool | Maintainer | License | Rationale |
|----------|------|------------|---------|-----------|
| SAST | bandit | PyCQA | Apache-2.0 | Python security linter, CWE mapping, plugin system |
| SCA | pip-audit | PyPA | Apache-2.0 | Official PyPA tool, OSV + PyPI advisory DB |

**Alternatives considered:**
- safety: Commercial database dependency, limited free tier
- pyre-check (Meta): Type-focused, not security-specific

### JavaScript/Node.js

| Category | Tool | Maintainer | License | Rationale |
|----------|------|------------|---------|-----------|
| SAST | semgrep | Semgrep Inc. | LGPL-2.1 | JS/TS rules, taint tracking, framework support |
| SCA | npm audit | npm/Microsoft | Artistic-2.0 | Built-in, GitHub Advisory Database |
| SCA (alt) | retire.js | OWASP | Apache-2.0 | Known-vulnerable library detection |

**Alternatives considered:**
- snyk: Excellent but commercial
- yarn audit / pnpm audit: Equivalent to npm audit for those package managers

### Terraform/OpenTofu

| Category | Tool | Maintainer | License | Rationale |
|----------|------|------------|---------|-----------|
| SAST | semgrep | Semgrep Inc. | LGPL-2.1 | HCL rules, misconfig detection |
| SCA | osv-scanner | Google OSS Security | Apache-2.0 | Scans .terraform.lock.hcl |

**NOT RECOMMENDED:**
- tfsec: Aqua Security (excluded per [ADR-0004](ADR-0004-supply-chain-security.md))
- trivy: Aqua Security (excluded per [ADR-0004](ADR-0004-supply-chain-security.md))

**Alternatives considered:**
- checkov (Bridgecrew/Palo Alto): Good alternative, policy-as-code

## Tool Summary by Hook ID

| Hook ID | Category | Language | Tool |
|---------|----------|----------|------|
| gosec | SAST | Go | gosec |
| govulncheck | SCA | Go | govulncheck |
| bandit | SAST | Python | bandit |
| pip-audit | SCA | Python | pip-audit |
| npm-audit | SCA | JavaScript | npm audit |
| yarn-audit | SCA | JavaScript | yarn audit |
| pnpm-audit | SCA | JavaScript | pnpm audit |
| retire-js | SAST/SCA | JavaScript | retire.js |
| semgrep | SAST | Universal | semgrep |
| osv-scanner | SCA | Universal | osv-scanner |
| osv-scanner-lockfile | SCA | Universal | osv-scanner |
| syft | SBOM | Universal | syft |
| grype | SCA | Container | grype |

## Consequences

### Positive

1. **Compliance coverage**: SAST + SCA for all supported languages satisfies SA-11(1), RA-5, SSDF PW.4/PW.7/RV.1
2. **Trusted sources**: All tools from foundations, major vendors, or established OSS communities
3. **No Aqua dependency**: Maintains supply chain boundary from [ADR-0004](ADR-0004-supply-chain-security.md)
4. **Consistent pattern**: Each language has one SAST + one SCA default

### Negative

1. **Multiple tools**: Teams must install language-specific tools (grouped in selective `brewfiles/<profile>.Brewfile` bundles)
2. **Overlap**: semgrep covers multiple languages but language-specific tools are deeper
3. **Maintenance**: More tools to keep updated

### Neutral

1. **Learning curve**: Developers familiar with ecosystem tools (e.g., Go devs know govulncheck)
2. **CI integration**: All tools have SARIF output for dashboard integration

## References

- [NIST SP 800-53 SA-11](https://csrc.nist.gov/projects/cprt/catalog#/cprt/framework/version/SP_800_53_5_1_1/home?element=SA-11)
- [NIST SP 800-53 RA-5](https://csrc.nist.gov/projects/cprt/catalog#/cprt/framework/version/SP_800_53_5_1_1/home?element=RA-5)
- [SSDF v1.1](https://csrc.nist.gov/publications/detail/sp/800-218/final)
- [OSV Database](https://osv.dev/)
- [Go Vulnerability Database](https://vuln.go.dev/)
- [PyPI Advisory Database](https://github.com/pypa/advisory-database)
- [GitHub Advisory Database](https://github.com/advisories)
- [ADR-0004: Supply Chain Security Tool Selection](ADR-0004-supply-chain-security.md)
