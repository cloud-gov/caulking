# ADR-0009: Gitleaks via the Upstream Hook + Caulking (not a bundled wrapper)

**Status:** Accepted
**Date:** 2026-07-22
**Deciders:** Cloud.gov Platform Team
**Supersedes:** [ADR-0007](ADR-0007-caulking-aware-gitleaks.md)
**Provenance:** Originally recorded as ADR-0007 in cloud-gov/pre-commit-templates prior to repository consolidation into cloud-gov/caulking ([ADR-0002](ADR-0002-template-consolidation-and-brewfile-bundles.md)).

## Context

[ADR-0007](ADR-0007-caulking-aware-gitleaks.md) shipped a cloud-gov "caulking-aware"
gitleaks hook (`scripts/gitleaks-unless-caulking.sh`, `language: golang`) intended to
delegate to caulking on workstations and self-install gitleaks in CI.

End-to-end testing in a clean `golang` container found it **never worked in CI**:

1. **`entry` path resolution.** pre-commit runs a `language: golang` hook's `entry`
   from the **consumer repo's** working directory, not the hook repo. A
   repo-relative script (`scripts/gitleaks-unless-caulking.sh`) is therefore "not
   found" in any consuming repo. Self-installing `language: golang` hooks only work
   with a **bare binary** entry that lands on the env `PATH` (e.g. `gosec`,
   `gitleaks`) — not a wrapper script.
2. Even setting that aside, a `language: golang` `repo: local` hook requires the
   hook repo to be a Go module (fixed separately in [ADR-0008](ADR-0008-selfcontained-hook-variants.md)'s `go.mod`).

So a bundled shell-wrapper hook and `language: golang` self-install are
**structurally incompatible**. A 7-voter consensus panel unanimously chose
**Option C** below.

## Decision

**The `.pre-commit-hooks.yaml` catalog ships no gitleaks hook.** Secret scanning is
handled per environment by the mechanism that already owns it:

- **Caulking workstations:** caulking runs gitleaks globally on every commit via its
  `core.hooksPath` wrapper (`hooks/hook-wrapper.sh`) before invoking `.pre-commit-config.yaml`.
  The hook catalog adds nothing there.
  > **Warning:** Do **not** export `SKIP=gitleaks` globally in shell profiles on a
  > caulking workstation to deduplicate against an upstream CI gitleaks hook —
  > caulking's global hook wrapper honors `SKIP=gitleaks` as a break-glass bypass,
  > so setting it globally disables workstation secret scanning entirely. Instead,
  > run gitleaks in CI via a dedicated CI step or scope any `SKIP` only to the inner
  > `pre-commit` runner invocation when caulking's outer gitleaks scan has already
  > succeeded.
- **CI / containers / devcontainers (no caulking):** consumers use **gitleaks'
  own upstream pre-commit hook** — `github.com/gitleaks/gitleaks`, which is a real
  Go module, `language: golang`, bare `gitleaks` entry (so it self-installs
  correctly) — pinned by `rev`. Wired in
  `starter-configs/go-repo-selfcontained.pre-commit-config.yaml`.

`scripts/gitleaks-unless-caulking.sh` is removed (preserved out-of-repo for
history). [ADR-0007](ADR-0007-caulking-aware-gitleaks.md) is superseded.

## Consequences

### Positive
- **Actually works in CI** (the upstream hook uses the only pattern pre-commit
  supports for a self-installing Go tool).
- **No double-scan** on workstations for standard starter configs (hook catalog ships
  no gitleaks hook; caulking's global wrapper owns it).
- **Fail-closed & auditable:** the upstream hook genuinely installs a **pinned**
  gitleaks and scans; there is no bespoke wrapper with skip branches to fail open
  (a prior review had to fix exactly such fail-opens in the removed wrapper).
- **Low maintenance:** cloud-gov no longer owns gitleaks pre-commit hook plumbing;
  the gitleaks project maintains its own hook.

### Negative
- No single cloud-gov-branded "caulking-aware" pre-commit hook.
- Two mechanisms for two environments (caulking global hook wrapper vs. upstream CI
  hook), and operators must never set `SKIP=gitleaks` globally in workstation shell
  profiles because doing so would also bypass caulking's global gitleaks check.

### Neutral
- The removed wrapper's fail-closed/autodetect design is preserved in
  [ADR-0007](ADR-0007-caulking-aware-gitleaks.md) for historical reference.

## References
- [ADR-0007](ADR-0007-caulking-aware-gitleaks.md) (superseded — the wrapper approach and why it failed)
- [ADR-0008](ADR-0008-selfcontained-hook-variants.md) (repo-root `go.mod` for `language: golang` `repo: local` hooks)
- Issue #35 (original caulking-aware hook — never worked in CI), #36 (self-contained variants)
- gitleaks upstream hook: https://github.com/gitleaks/gitleaks/blob/master/.pre-commit-hooks.yaml
- [pre-commit supported languages](https://pre-commit.com/#supported-languages)
