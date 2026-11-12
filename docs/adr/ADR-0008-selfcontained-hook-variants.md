# ADR-0008: Self-Contained Hook Variants for Linux / CI / Containers

**Status:** Accepted
**Date:** 2026-07-22
**Deciders:** Cloud.gov Platform Team
**Provenance:** Originally recorded as ADR-0006 in cloud-gov/pre-commit-templates prior to repository consolidation into cloud-gov/caulking ([ADR-0002](ADR-0002-template-consolidation-and-brewfile-bundles.md)).

## Context

The hook catalog's Go and shell hooks use `language: unsupported` (formerly
`language: system`), which pre-commit does **not** install — it requires the tool
already on `PATH`. That is correct for caulking **macOS workstations** (tools come
from selective `brewfiles/<profile>.Brewfile` bundles), but it **fails in a bare
Linux workstation, CI runner, or container/devcontainer** where nothing is
pre-installed: `pre-commit run` errors with "executable not found."

[ADR-0007](ADR-0007-caulking-aware-gitleaks.md) proved the remedy for Go tools:
`language: golang` with a pinned `additional_dependencies` makes pre-commit install
the tool into an isolated environment, and pre-commit ≥ 3.0.0 bootstraps the Go
toolchain itself — so it runs in a clean sandbox. Issue #36 asked whether to
generalize that to the other Go/shell scanners, and how, without breaking the many
repos that consume the hook catalog by pinned rev.

A 7-voter consensus panel (architect / security / devex / ai_ml / pm / contrarian /
scope-steward) evaluated three shapes and chose **Option A** unanimously
(several also recommending we ship an example config — a hybrid A+B):

- **Rejected — change existing ids in place** (`unsupported` → `golang`): a silent
  breaking change for every consumer on their next rev bump (first run now needs
  network + a Go toolchain), breaking offline/air-gapped consumers. MAJOR churn for
  no functional gain to existing users.
- **Rejected as sole solution — example config only:** the self-installing
  gosec/govulncheck would be `repo: local` blocks each consumer copy-pastes (a DRY
  violation with fragmented version pinning); the template itself would ship no
  reusable self-installing hook. Kept as *documentation* on top of Option A.
- **Chosen — new opt-in ids alongside the existing ones.**

## Decision

Add **`-selfcontained`** Go hook ids to `.pre-commit-hooks.yaml`, alongside (not
replacing) the existing `unsupported` ids:

| new id | language | tool source |
|--------|----------|-------------|
| `gofmt-selfcontained` | `golang` | Go toolchain (pre-commit-bootstrapped) |
| `go-vet-selfcontained` | `golang` | Go toolchain |
| `gosec-selfcontained` | `golang` | pinned `additional_dependencies: github.com/securego/gosec/v2/cmd/gosec@v2.28.0` (no official hook repo) |
| `govulncheck-selfcontained` | `golang` | pinned `additional_dependencies: golang.org/x/vuln/cmd/govulncheck@v1.6.0` (no official hook repo) |

For the tools that already have good self-installing upstream hook repos, the
example config points at them directly rather than re-wrapping:
`golangci/golangci-lint` (`language: golang`), `shellcheck-py/shellcheck-py`
(`language: python`, bundled binary), `scop/pre-commit-shfmt` `shfmt-src`
(`language: golang`).

Ship `starter-configs/go-repo-selfcontained.pre-commit-config.yaml` wiring all of the
above with pinned revs and `minimum_pre_commit_version: "3.0.0"`.

The existing `unsupported` ids are **unchanged** — macOS/caulking and offline consumers
are unaffected and pick their model by id.

## Consequences

### Positive
- Linux/CI/container consumers get working Go/shell scanners from one config, with
  nothing pre-installed. Directly advances the deferred #24 (Linux/CI install).
- Pinned versions live centrally in the hook catalog, so a security bump to
  gosec/govulncheck propagates to all `-selfcontained` consumers via one rev.
- Existing consumers experience **no change** (no forced version floor, no new
  network dependency).

### Negative
- Catalog growth (~4 new ids) and "two ways to do the same thing" — mitigated by
  the `-selfcontained` naming convention and this ADR.
- The `-selfcontained` hooks require pre-commit ≥ 3.0.0 and **network on first
  run** (compile/download once, then cached). Fully offline/air-gapped consumers
  must keep the `unsupported` ids or pre-warm the pre-commit cache. This is documented
  on the ids and in the example.
- **govulncheck additionally needs network at RUN time** (it fetches the vuln DB
  from `vuln.go.dev` every run). Behind a TLS-inspection proxy (e.g. Zscaler) the
  environment must trust the corporate root CA, or use `govulncheck -db <mirror>`;
  otherwise it fails with an x509 "unknown authority" error. `make
  test-selfcontained` auto-trusts a host Zscaler CA when present so the guard is
  reliable locally, and needs none in clean-egress CI.
- Each `language: golang` `repo: local` hook requires a repo-root `go.mod`
  (pre-commit always runs `go install ./...` in the hook repo). Added as an empty
  module (no `tools.go`, no `require`) so tool versions stay single-sourced in
  `additional_dependencies`.
- `shellcheck-py` and `scop/pre-commit-shfmt` are community-maintained wrappers
  (not vendor-official) — an accepted supply-chain note (see [ADR-0004](ADR-0004-supply-chain-security.md)); versions
  are pinned.

### Neutral
- Uses `language: golang`/`python`, distinct from the repo's `unsupported` default —
  intentional and confined to the opt-in variants. Coordinates with #34, which
  keeps the default hooks on `unsupported`.

## References
- Issue #36 (self-contained variants); #24 (Linux/CI install); #34 (language policy)
- [ADR-0007](ADR-0007-caulking-aware-gitleaks.md) (caulking-aware gitleaks — the proving ground for `language: golang`)
- [ADR-0004](ADR-0004-supply-chain-security.md) (supply-chain assessment), [ADR-0006](ADR-0006-language-security-tools.md) (Go tool selection)
- [pre-commit supported languages](https://pre-commit.com/#supported-languages)
