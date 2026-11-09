# ADR-0004: Supply Chain Security Tool Selection

**Status:** Accepted  
**Date:** 2026-05-18  
**Deciders:** GSA-TTS Agentic Coding Team  
**Provenance:** Originally recorded as ADR-0002 in cloud-gov/pre-commit-templates prior to repository consolidation into cloud-gov/caulking ([ADR-0002](ADR-0002-template-consolidation-and-brewfile-bundles.md)).

## Context

Pre-commit hooks execute third-party tools in developer environments and CI/CD pipelines. These tools have direct access to source code and can influence the software supply chain. We must evaluate each tool for:

1. **Ownership and governance** - Who controls the project?
2. **Supply chain integrity** - Are binaries signed? Are there known CVEs?
3. **License compatibility** - Is the license federal-friendly?
4. **Aqua Security exclusion** - Due to ongoing supply chain concerns, Aqua Security tools (trivy, tracee, etc.) are excluded.

## Decision

### Important: Tools Are Recommendations, Not Requirements

**All tools in this repository are EXAMPLES subject to team override.** Teams may:
- Select alternative tools that better fit their technology stack
- Omit tools not relevant to their project
- Add additional tools after performing their own security assessment
- Use different versions based on project compatibility

The tools listed here have been security-assessed and are pre-approved for use, but teams retain authority over their toolchain decisions.

### Approved Tools (LOW risk)

| Tool | Owner | License | Risk | Notes |
|------|-------|---------|------|-------|
| pre-commit | Anthony Sottile | MIT | LOW | 10+ year track record, no CVEs |
| shellcheck | Vidar Holen | GPL-3.0 | LOW | Single maintainer, but 13+ year history |
| shfmt | Daniel Martí | BSD-3 | LOW | Single maintainer, well-distributed |
| ruff | Astral/OpenAI | MIT | LOW | VC-backed, OpenAI acquisition |
| mypy | Python/PSF | MIT | LOW | Foundation governance, 13 maintainers |
| golangci-lint | Community | GPL-3.0 | LOW | Multi-maintainer, SBOMs provided |
| ruby | Ruby Core Team | Ruby/BSD-2-Clause | LOW | Multi-decade core language governance |
| rubocop | RuboCop Core Team | MIT | LOW | Community governance, standard Ruby analyzer |
| yamllint | Adrien Vergé | GPL-3.0 | LOW | Read-only Python YAML linter, widely packaged |
| actionlint | rhysd | MIT | LOW | Static GitHub Actions workflow analyzer |
| markdownlint-cli | Igor Shubovych / David Anson | MIT | LOW | Standard Markdown CLI linter |
| hadolint | Community | GPL-3.0 | LOW | No CVEs, read-only operation |
| tflint | terraform-linters | MPL-2.0/BUSL | LOW-MEDIUM | Attestation support, plugin model |
| git-cliff | orhun | Apache-2.0/MIT | LOW | Single maintainer, monitor quarterly |
| semgrep | Semgrep Inc. | LGPL-2.1 | LOW | US company, NOT Aqua-affiliated |
| grype | Anchore Inc. | Apache-2.0 | LOW | US company, NOT Aqua-affiliated |

### JavaScript/TypeScript Tools (LOW risk)

| Tool | Owner | License | Risk | Notes |
|------|-------|---------|------|-------|
| eslint | OpenJS Foundation | MIT | LOW | Foundation governance, industry standard |
| prettier | Community | MIT | LOW | Zero dependencies, widely adopted |
| typescript | Microsoft | Apache-2.0 | LOW | Enterprise governance, zero deps |
| biome | Community | MIT/Apache-2.0 | LOW-MEDIUM | Rust-based, faster alternative |

**Alternative Considerations:**
- **Biome** can replace both ESLint and Prettier with a single, faster tool
- Teams may prefer **deno lint** or **oxlint** for specific use cases
- **Rome** is deprecated; use Biome instead

### Terraform vs OpenTofu

| Factor | Terraform | OpenTofu |
|--------|-----------|----------|
| License | BSL 1.1 (NOT OSI) | MPL-2.0 (OSI) |
| Governance | HashiCorp/IBM | Linux Foundation |
| Risk | MEDIUM | LOW |
| Recommendation | Supported | **Recommended** |

**Decision:** Support both Terraform and OpenTofu hooks. Teams can choose based on their requirements. OpenTofu is recommended for new projects due to:
- OSI-approved open source license (MPL-2.0)
- Linux Foundation governance (vendor-neutral)
- No license ambiguity for federal procurement

### Excluded Tools

| Tool | Owner | Reason |
|------|-------|--------|
| trivy | Aqua Security | Supply chain security concerns |
| tracee | Aqua Security | Supply chain security concerns |
| kube-bench | Aqua Security | Supply chain security concerns |

### Single-Maintainer Risk Acceptance

Several tools have single-maintainer risk (shellcheck, shfmt, git-cliff). We accept this risk with monitoring because:
- All have clean security track records (0 CVEs)
- All are read-only static analysis tools (limited attack surface)
- All are widely distributed via package managers (additional vetting)
- Quarterly monitoring will detect abandonment

**Monitoring requirements:**
- Track GitHub activity quarterly
- Document backup alternatives
- Review before major version upgrades

## Team Override Process

Teams wishing to use alternative tools should:

1. **Document the alternative** in their project's README or ADR
2. **Verify security posture** - Check for CVEs, review maintainer governance
3. **Confirm license compatibility** - Ensure federal-friendly licensing
4. **Notify security team** if adding tools not in this pre-approved list

No approval is required to omit tools or select from the approved alternatives.

## Consequences

### Positive
- Clear criteria for tool selection
- Documented supply chain risk assessment
- Excludes known problematic vendors
- Supports both Terraform and OpenTofu for team flexibility
- Teams retain override authority

### Negative
- Single-maintainer tools have continuity risk
- More tools to monitor quarterly
- Teams must choose between Terraform/OpenTofu hooks

### Neutral
- Semgrep and Grype add security scanning capability
- OpenTofu hooks duplicate Terraform hooks (intentional for choice)
- JS/TS tools require npm installation (project-local preferred)

## References

- [NIST SP 800-53 SA-12: Supply Chain Protection](https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final)
- [OpenTofu announcement](https://opentofu.org/announcement)
- [Terraform BSL license change](https://www.hashicorp.com/license-faq)
- Supply chain security assessments performed 2026-05-18

## Compliance

This ADR addresses:
- **SA-12** (Supply Chain Protection) - Tool vetting and monitoring
- **CM-7** (Least Functionality) - Only approved tools in toolchain
- **RA-5** (Vulnerability Scanning) - CVE review for all tools
