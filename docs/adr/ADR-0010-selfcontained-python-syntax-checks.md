# ADR-0010: Self-Contained Python Syntax Checks

**Status:** Accepted
**Date:** 2026-11-05
**Deciders:** Cloud.gov Platform Team
**Provenance:** Originally recorded as ADR-0009 in cloud-gov/pre-commit-templates prior to repository consolidation into cloud-gov/caulking ([ADR-0002](ADR-0002-template-consolidation-and-brewfile-bundles.md)).

## Context

The existing `check-yaml` and `check-json` hooks use ambient `python3`, and
`check-yaml` also needs ambient PyYAML. Consumers in Linux CI, containers, or
macOS environments without that dependency need an opt-in isolated alternative.
Existing consumers must retain their current hook behavior.

## Decision

Add `check-yaml-selfcontained` and `check-json-selfcontained` with
`language: python`. A minimal root `pyproject.toml` installs the dedicated
`cloud_gov_pre_commit_checks` package and module entry point. Explicit package
selection avoids packaging unrelated directories and coexists with the existing
dependency-free Go module. The internal package version is not a hook catalog
release; consumers pin the provider's Git revision.

Keep runtime dependencies out of package metadata. Pin `PyYAML==6.0.3` in the
YAML hook's `additional_dependencies`, and import YAML lazily. The JSON hook uses
only the standard library and installs no PyYAML. Pre-commit separates environments
by their additional dependencies. Run the installed environment's Python with
`python -I -m cloud_gov_pre_commit_checks yaml` (or `json`), dispatching through
`__main__.py`. Isolated mode ignores `PYTHONPATH` and the consumer working directory,
preventing a local `yaml.py` from shadowing the dependency. Console scripts alone
do not provide this protection, so none are published.

Use UTF-8 text input, `yaml.safe_load` for single-document safe YAML, and
`json.load` for JSON. Preserve standard-library JSON semantics, including BOM
rejection and acceptance of duplicate keys and non-finite numbers. Report filename
and parser/read diagnostics (including parser `ValueError`s for invalid YAML
timestamps or JSON integer conversion limits) for every failing input, return nonzero, and never
modify inputs. Keep legacy hook definitions unchanged.

## Consequences

### Positive

- Hooks work independently of caulking and ambient PyYAML on macOS and Linux.
- JSON does not install a YAML dependency; YAML has an auditable exact runtime pin.
- Safe loading rejects Python object constructors without executing them.
- Existing consumers opt in explicitly without a language-alias migration.

### Negative

- Python 3.9+ must be available; `language: python` does not bootstrap Python.
- First use needs package-index access for build tooling and YAML's dependency,
  or a pre-warmed cache. Build tooling is not an exact-version runtime lock.
- The PyYAML pin needs maintenance, and environments consume cache space.

### Neutral

- Consumers own CI configuration and select these hook IDs at a revision containing
  them in `cloud-gov/caulking`.
- The existing Go hook module and workstation toolchain remain independent.

## References

- [Pre-commit Python language](https://pre-commit.com/#python)
- [Pre-commit try-repo](https://pre-commit.com/#pre-commit-try-repo)
- [PyYAML 6.0.3](https://pypi.org/project/PyYAML/6.0.3/)
- [PyYAML safe_load](https://pyyaml.org/wiki/PyYAMLDocumentation)
- [ADR-0008](ADR-0008-selfcontained-hook-variants.md)
