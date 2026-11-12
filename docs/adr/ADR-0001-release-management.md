# ADR-0001: GitHub Actions Release Please and Stable SemVer Tags

**Status:** Accepted
**Date:** 2026-11-08
**Deciders:** William Zujkowski

## Context

Caulking has a historical VERSION and changelog but no published release tags and
no current Release Please configuration. Consumers need a clear stable revision.
William selected GitHub Actions as the initial release automation environment.

## Decision

Use Google's Release Please with a SHA-pinned GitHub Action, one root simple
strategy, plain VERSION, matching manifest, generated changelog, and immutable
v-prefixed SemVer tags. Maintainers review release PRs before publication.
Latest published non-prerelease is stable; main is development. Enforce
Conventional PR titles and use squash commit subjects for version calculation.
Record architectural/tooling decisions in MADR under docs/adr.

Keep external tool lifecycle separate: Brewfiles select packages, compatibility
checks enforce supported minimums, and users upgrade tools with Homebrew.

## Consequences

### Positive

- Discoverable stable releases and generated release notes.
- Reviewable version bumps without manually moving tags.
- Tool updates do not force a caulking release for every upstream patch.

### Negative

- Repository permissions and release-PR required checks need maintainer setup.
- Historical version labels require reconciliation during the first release.

### Neutral

- No release is published merely by adding local configuration.
- Existing package-level compatibility limits still require testing.

## References

- [Release contract and setup](../releases.md).
- https://github.com/googleapis/release-please
- https://www.conventionalcommits.org/
- https://semver.org/
- https://adr.github.io/madr/
