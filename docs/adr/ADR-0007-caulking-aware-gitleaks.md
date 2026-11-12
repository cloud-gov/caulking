# ADR-0007: Caulking-Aware Gitleaks Hook

**Status:** Superseded by [ADR-0009](ADR-0009-gitleaks-via-upstream-hook.md) (2026-07-22)
**Date:** 2026-07-22
**Deciders:** Cloud.gov Platform Team
**Provenance:** Originally recorded as ADR-0005 in cloud-gov/pre-commit-templates prior to repository consolidation into cloud-gov/caulking ([ADR-0002](ADR-0002-template-consolidation-and-brewfile-bundles.md)).

> **SUPERSEDED.** The caulking-aware wrapper hook described here (`scripts/
> gitleaks-unless-caulking.sh`, shipped as a `language: golang` hook) **never
> worked in CI**: pre-commit resolves a `language: golang` hook's `entry` against
> the *consumer* repo's working directory, not the hook repo, so the wrapper
> script was "not found" in any consuming repo. Confirmed in a clean container.
> [ADR-0009](ADR-0009-gitleaks-via-upstream-hook.md) replaces this with Option C:
> the hook catalog ships no gitleaks hook; CI uses gitleaks' own upstream
> pre-commit hook, and caulking covers workstations. The rest of this ADR is
> retained for the decision trail.

---

## Context

[Caulking](https://github.com/cloud-gov/caulking) is cloud.gov's global git-hooks
manager. It sets `core.hooksPath` globally and runs **gitleaks** on every commit as
a mandatory secret-detection control for cloud.gov developer workstations.

Because of that, the reusable hook catalog historically shipped **no** gitleaks hook,
to avoid a duplicate scan on developer machines (documented in `AGENTS.md` and
[ADR-0004](ADR-0004-supply-chain-security.md)). The stated fallback was: *"For CI
environments (where caulking is not available), teams must add gitleaks to their CI
pipeline directly."*

That fallback is a gap:

- **Consuming repos get no secret-scanning in environments without caulking** —
  CI runners, Docker sandboxes, devcontainers, contractor laptops without caulking.
  Each team is expected to hand-roll gitleaks in CI; in practice many do not, so
  the same `.pre-commit-config.yaml` that is fully protected on a caulking laptop is
  **unprotected** in CI.
- The gap is invisible: a green pre-commit run in CI does not indicate that secrets
  were scanned, only that no gitleaks hook ran.

We want secret-scanning to be present **everywhere** a consuming repo runs
pre-commit, **without** double-scanning on caulking workstations, from a single
`.pre-commit-config.yaml`.

## Decision

Add a single **caulking-aware `gitleaks` hook** (`scripts/gitleaks-unless-caulking.sh`)
that:

1. **Autodetects** whether caulking already owns gitleaks and, if so, **delegates**
   (skips its own scan) — no duplicate scan on developer machines.
2. Otherwise **runs gitleaks itself**, using `language: golang` with a pinned
   `additional_dependencies` entry so pre-commit self-installs gitleaks into an
   isolated environment. This works in a bare CI runner / container / devcontainer
   with no pre-installed tools.

### Fail-closed autodetection (a security control must bias toward scanning)

This is a secret-detection control, so the **default bias is to SCAN**; we skip our
own scan *only* when we can positively prove a scan will otherwise happen. Any
ambiguity results in a local scan, never a skip. Caulking is treated as "provably
owning gitleaks" only when **both** of these hold:

1. `core.hooksPath` points at a `pre-commit` wrapper that carries a
   **caulking-specific marker** (`hook-wrapper.sh` / "Caulking") — so we don't
   mistake an unrelated `hooksPath` for caulking; **and**
2. that wrapper contains a line that **actually executes** gitleaks (a
   `[run_]gitleaks` command at a statement position), after comments are stripped —
   so a mere *mention* of the word (a comment, a disabled path, a "we removed
   gitleaks" note) does **not** count.

Requirement (2) closes an earlier **fail-open**: an unanchored substring match for
`gitleaks` would let any wrapper that merely contains the string disable scanning.
That is exactly the direction a security control must not fail.

The decision is **always announced on stderr** so it is observable. Overrides:

- `GITLEAKS_DELEGATE_TO_CAULKING=0` — always run locally, even under caulking.
- `GITLEAKS_DELEGATE_TO_CAULKING=1` — delegate **only if caulking is also detected**;
  in an environment with no detected caulking (e.g. CI) it **warns and scans anyway**.
  An environment variable alone can never silently disable secret scanning.
- `SKIP=gitleaks` — the single explicit, auditable break-glass to skip entirely
  (the standard pre-commit convention).

### Scope parity with caulking

The local scan runs `gitleaks git --staged --redact`. Caulking's own wrapper
(verified) runs `gitleaks git --staged` for the pre-commit stage (plus
`--log-opts` ranges on pre-push), so the delegated and local pre-commit scopes
match — delegation is a like-for-like substitute at commit time.

### Why `language: golang` (not `system` or `docker`)

- `system` (the default in this repo) does **not** install anything — it requires
  gitleaks already on PATH, which is exactly what a bare sandbox lacks. That is the
  gap we are closing, so `system` is unsuitable here.
- `docker`/`docker_image` would need a Docker daemon, frequently unavailable or
  rootless-restricted in CI sandboxes.
- `golang` makes pre-commit `go install` a **pinned** gitleaks into an isolated
  GOPATH (pre-commit ≥ 3.0.0 also bootstraps the Go toolchain), so the hook is
  self-contained on both macOS and Linux. This is the one hook where we deviate from
  the repo's `system` default, and it is deliberate: a security control must be able
  to run where no tools are pre-installed.

Module pinned: `github.com/zricethezav/gitleaks/v8@v8.30.1` (canonical module path
per the project's `go.mod`; `github.com/gitleaks/gitleaks` redirects to it).

### Also fixed in the same change

`trailing-whitespace` previously used an inline `sed -i '' …` entry that is
**macOS-only** and errors on Linux (GNU `sed -i` takes a different in-place suffix
argument). Since this hook now genuinely runs in Linux CI/sandboxes, it was moved to
a portable `scripts/trailing-whitespace.sh` (mktemp + atomic `mv`, matching
`end-of-file-fixer.sh`), consistent with the repo's macOS-and-Linux requirement.

## Consequences

### Positive

- Consuming repos get secret-scanning in **all** environments from one config; the
  CI gap closes with no per-team action.
- **No duplicate scan** on caulking workstations (delegation is autodetected).
- The `trailing-whitespace` Linux bug is fixed, unblocking Linux/CI use of the whole
  template.
- Behavior is observable (announced) and overridable (env vars + `SKIP`).

### Negative

- First run in a caulking-less environment compiles/installs gitleaks (slow once,
  cached after) and needs network (GOPROXY). A fully offline sandbox must pre-warm
  the pre-commit cache. (Same tradeoff as any self-installing hook.)
- This is the only hook using `language: golang` rather than the repo's `system`
  default — a small, intentional inconsistency documented here.
- Delegation detection depends on caulking keeping a recognizable marker AND an
  executed-gitleaks line in its wrapper. If caulking restructures its wrapper such
  that neither is detectable, this hook falls back to **running gitleaks locally**
  (a redundant scan on a caulking box — safe: an extra scan, never a missed one).
  The env overrides remain available.

### Neutral

- Teams already running gitleaks in CI by hand can drop that step, or set
  `GITLEAKS_DELEGATE_TO_CAULKING` explicitly if they prefer their own invocation.

## References

- `scripts/gitleaks-unless-caulking.sh` — the removed hook implementation
- [ADR-0004](ADR-0004-supply-chain-security.md) — supply-chain security assessment
- [ADR-0009](ADR-0009-gitleaks-via-upstream-hook.md) — superseding decision
- [Caulking](https://github.com/cloud-gov/caulking)
- [gitleaks](https://github.com/gitleaks/gitleaks)
- [pre-commit supported languages](https://pre-commit.com/#supported-languages)
