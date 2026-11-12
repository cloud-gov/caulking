# ADR-0005: JavaScript/TypeScript Tool Selection

**Status:** Accepted
**Date:** 2026-05-19
**Deciders:** Cloud.gov Platform Team
**Provenance:** Originally recorded as ADR-0003 in cloud-gov/pre-commit-templates prior to repository consolidation into cloud-gov/caulking ([ADR-0002](ADR-0002-template-consolidation-and-brewfile-bundles.md)).

## Context

The `cloud-gov/caulking` repository (consolidating `pre-commit-templates`) provides reusable pre-commit hooks for multiple languages used across GSA-TTS projects. JavaScript and TypeScript are widely adopted in federal web applications, requiring standardized tooling for:

- **Linting**: Enforce code quality, detect bugs, prevent anti-patterns
- **Formatting**: Ensure consistent code style across teams

Unlike Python (single binary via pipx) or Go (single binary), the JavaScript ecosystem lacks universally-installed tooling. Node.js projects typically install linting/formatting tools as `devDependencies` and execute them via `npx`. This creates a dependency model where:

1. Hooks require Node.js runtime (user-installed)
2. Hooks expect project-local tools in `node_modules/` (project-installed)
3. Hooks execute via `npx <tool>` to locate the correct version

### Options Evaluated

**Option A: ESLint + Prettier (Separate Tools)**
- ESLint: Industry-standard linter, configurable via plugins (React, TypeScript, etc.)
- Prettier: Opinionated formatter, zero-config by default
- Ecosystem: Mature, widely adopted in federal projects (18F, GSA, USDS)
- Trade-off: Two tools = two configs, occasional overlap (e.g., quote style)

**Option B: Biome (Unified Toolchain)**
- Biome: Single Rust-based binary for linting + formatting
- Performance: 10-25x faster than ESLint+Prettier (Rust vs Node.js)
- Trade-off: Newer tool (stable as of v1.0), smaller plugin ecosystem

**Option C: Standard.js (Zero-Config)**
- Standard: Opinionated linter/formatter, no config files
- Trade-off: Not configurable, conflicts with agency style guides

Federal projects require both **configurability** (agency-specific rules) and **maturity** (ATO compliance, audit trails). Option C fails configurability. Option B offers performance but lacks ecosystem maturity for risk-averse environments.

## Decision

We provide **two hook options** for JavaScript/TypeScript:

### Primary: ESLint + Prettier

```yaml
- repo: https://github.com/cloud-gov/caulking
  rev: v0.1.0
  hooks:
    - id: eslint
    - id: prettier
```

### Alternative: Biome

```yaml
- repo: https://github.com/cloud-gov/caulking
  rev: v0.1.0
  hooks:
    - id: biome-check
```

### Tool Execution Model

All hooks execute via `npx`:

```yaml
- id: eslint
  name: ESLint
  entry: npx eslint --fix
  language: unsupported
  types_or: [javascript, jsx, ts, tsx]
```

**Requirements:**
- **Runtime**: Node.js >= 18.x (installed via `brewfiles/javascript.Brewfile` or user-installed)
- **Tools**: Project must declare tools in `devDependencies` (or install `biome` via `brewfiles/javascript.Brewfile`)
- **Execution**: `npx` locates tools in `node_modules/.bin/`

### Rationale for ESLint + Prettier as Primary

1. **Federal adoption**: Used by 18F, GSA.gov, Login.gov, USDS projects
2. **Audit trail**: ESLint has CVE history, security disclosures, SBOM support
3. **Plugin ecosystem**: TypeScript, React, accessibility (jsx-a11y), security
4. **Configurable**: Supports agency style guides
5. **ATO precedent**: Already authorized in GSA Moderate systems

### Rationale for Biome as Alternative

1. **Performance**: Significantly faster, critical for large monorepos
2. **Unified**: Single tool replaces both ESLint and Prettier
3. **Modern**: Better TypeScript support, import sorting built-in
4. **Future-proof**: Growing adoption in major organizations

### Version Pinning

Projects **must** pin exact versions in `package.json`:

```json
{
  "devDependencies": {
    "eslint": "9.2.0",
    "prettier": "3.2.5",
    "@biomejs/biome": "1.7.3"
  }
}
```

This prevents supply chain attacks via floating ranges (see [ADR-0004](ADR-0004-supply-chain-security.md)).

## Consequences

### Positive

- **Flexibility**: Projects choose ESLint+Prettier (mature) or Biome (fast)
- **Ecosystem alignment**: Respects Node.js conventions (npx, local deps)
- **Version control**: Project controls tool versions via package.json
- **Supply chain**: Lockfiles provide integrity verification ([ADR-0004](ADR-0004-supply-chain-security.md))
- **Gradual migration**: Teams can test Biome without abandoning ESLint

### Negative

- **Setup burden**: Projects must install Node.js + devDependencies before hooks work
- **Error modes**: Hook fails if Node.js missing or devDeps not installed
- **Two configs**: ESLint + Prettier require separate config files
- **Version drift**: Each project may use different versions

### Neutral

- **No global npm installs**: Hooks never install npm packages globally
- **No bundled tools**: Hook repo does not vendor binaries
- **Node.js assumption**: Assumes developers have Node.js installed (available via `brewfiles/javascript.Brewfile`)

## Related Decisions

- **[ADR-0003](ADR-0003-hook-selection.md)**: Hook selection principles (established one-tool-per-category pattern)
- **[ADR-0004](ADR-0004-supply-chain-security.md)**: Supply chain security assessment (requires exact version pinning)
- **[ADR-0006](ADR-0006-language-security-tools.md)**: Language-specific security tools (covers npm-audit for SCA)

## References

- [ESLint](https://eslint.org/) - OpenJS Foundation
- [Prettier](https://prettier.io/) - Prettier team
- [Biome](https://biomejs.dev/) - Biome team
- [npx documentation](https://docs.npmjs.com/cli/v10/commands/npx)
