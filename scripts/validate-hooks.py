#!/usr/bin/env python3
"""
Validate .pre-commit-hooks.yaml structure and content.

Checks:
- Required keys present (id, name, entry, language)
- language is a recognized value
- Valid YAML syntax

LANGUAGE POLICY (see issue #34):
  pre-commit 4.4.0 added `unsupported`/`unsupported_script` as ALIASES for
  `system`/`script`, noting the old names will "eventually" be deprecated — they
  are NOT yet deprecated-with-warning and NOT removed. Migrating this widely-
  consumed template to the new names would raise every consumer's minimum
  pre-commit to >=4.4.0 for zero functional benefit today.

  So this validator ACCEPTS BOTH spellings without error. `unsupported`/
  `unsupported_script` are the preferred forms for NEW hooks (emitted as a
  non-fatal stderr note), but shipping `system`/`script` remains valid for
  maximum consumer compatibility.

  MIGRATION TRIGGER: when pre-commit ships a real deprecation *warning* for
  `system`/`script`, flip PREFER_NEW_LANGUAGE_NAMES handling to a hard error,
  migrate the hooks, and release a MAJOR with `minimum_pre_commit_version: 4.4.0`.
  Track: https://github.com/pre-commit/pre-commit/blob/main/CHANGELOG.md
"""

import sys
from pathlib import Path

import yaml


def validate_hooks(filepath: str = ".pre-commit-hooks.yaml") -> tuple[list[str], int]:
    """Validate hook definitions and return (errors, hook_count)."""
    errors: list[str] = []

    # Check file exists
    path = Path(filepath)
    if not path.exists():
        return [f"File not found: {filepath}"], 0

    # Parse YAML
    try:
        with open(path, encoding="utf-8") as f:
            hooks = yaml.safe_load(f)
    except yaml.YAMLError as e:
        return [f"YAML parse error: {e}"], 0

    if not isinstance(hooks, list):
        return ["Expected a list of hooks"], 0

    hook_count = len(hooks)
    required_keys = ["id", "name", "entry", "language"]

    # Both the legacy and the 4.4.0+ alias names are accepted (issue #34).
    # `unsupported`/`unsupported_script` are preferred for new hooks; the legacy
    # `system`/`script` remain valid until pre-commit actually deprecates them.
    preferred_alias = {
        "system": "unsupported",
        "script": "unsupported_script",
    }
    # Any language pre-commit understands, plus the legacy aliases. Used only to
    # catch outright typos (e.g. "golangg"); NOT to force the alias migration.
    known_languages = {
        "system",
        "script",
        "unsupported",
        "unsupported_script",
        "python",
        "python_venv",
        "node",
        "golang",
        "rust",
        "ruby",
        "docker",
        "docker_image",
        "conda",
        "coursier",
        "dart",
        "dotnet",
        "fail",
        "haskell",
        "lua",
        "perl",
        "pygrep",
        "r",
        "swift",
    }

    for i, hook in enumerate(hooks):
        hook_id = hook.get("id", f"hook[{i}]")

        # Check required keys
        for key in required_keys:
            if key not in hook:
                errors.append(f'{hook_id}: missing required key "{key}"')

        # Language: accept both legacy and alias names; only error on an
        # unrecognized value (likely a typo). Nudge toward the alias as a
        # non-fatal note so guidance stays forward-looking without breaking the
        # build or forcing a version-floor bump (#34).
        lang = hook.get("language", "")
        if lang and lang not in known_languages:
            errors.append(
                f'{hook_id}: unrecognized language "{lang}" '
                f"(typo? expected one of pre-commit's supported languages)"
            )
        elif lang in preferred_alias:
            print(
                f"  Note: {hook_id} uses language: {lang}; "
                f'"{preferred_alias[lang]}" is preferred for new hooks '
                "(both accepted — see #34)",
                file=sys.stderr,
            )

        # Check for description (recommended) - warn to stderr
        if "description" not in hook:
            print(f"  Warning: {hook_id} has no description", file=sys.stderr)

        entry = str(hook.get("entry", ""))
        if lang in {"script", "unsupported_script"} and entry.startswith("scripts/"):
            script_path = path.parent / entry.split()[0]
            if (path.parent / "scripts").is_dir():
                if not script_path.is_file():
                    errors.append(f"{hook_id}: missing script entry {script_path}")
                elif not (script_path.stat().st_mode & 0o111):
                    errors.append(f"{hook_id}: script entry not executable {script_path}")

    if (path.parent / "starter-configs").is_dir() and (path.parent / "brewfiles").is_dir():
        errors.extend(validate_starter_configs(path.parent, hooks))

    return errors, hook_count


PROFILE_BINARIES: dict[str, set[str]] = {
    "baseline": {"gitleaks", "prek", "bash"},
    "shell": {"shellcheck", "shfmt"},
    "container": {"hadolint"},
    "python": {"ruff", "mypy", "bandit", "pip-audit"},
    "go": {"go", "gofmt", "golangci-lint"},
    "javascript": {"node", "npx", "npm"},
    "ruby": {"ruby", "rubocop"},
    "opentofu": {"tofu", "tflint"},
    "terraform": {"terraform", "tflint"},
    "docs": {"yamllint", "actionlint", "markdownlint"},
    "security": {"semgrep", "osv-scanner", "syft", "grype"},
}


def validate_starter_configs(root: Path, hooks: list[dict]) -> list[str]:
    """Validate starter-configs/*.yaml against .pre-commit-hooks.yaml and brewfiles/."""
    errors: list[str] = []
    hook_map = {h["id"]: h for h in hooks if isinstance(h, dict) and "id" in h}
    starter_files = sorted((root / "starter-configs").glob("*.pre-commit-config.yaml"))
    if not starter_files:
        return ["No starter-configs/*.pre-commit-config.yaml files found"]

    for cfg_path in starter_files:
        text = cfg_path.read_text(encoding="utf-8")
        lines = text.splitlines()
        declared_profiles: list[str] = []
        in_profiles = False
        for line in lines:
            if "Paired `.caulking-profiles`" in line:
                in_profiles = True
                continue
            if in_profiles:
                stripped = line.lstrip("#").strip()
                if not stripped or stripped.startswith("("):
                    break
                declared_profiles.append(stripped)

        if not declared_profiles or "baseline" not in declared_profiles:
            errors.append(
                f"{cfg_path.name}: missing Paired .caulking-profiles header with baseline"
            )
            continue

        available_bins: set[str] = set()
        for prof in declared_profiles:
            bf = root / "brewfiles" / f"{prof}.Brewfile"
            if not bf.is_file():
                errors.append(f"{cfg_path.name}: unknown profile '{prof}' (missing {bf.name})")
            available_bins.update(PROFILE_BINARIES.get(prof, set()))

        try:
            cfg = yaml.safe_load(text)
        except yaml.YAMLError as e:
            errors.append(f"{cfg_path.name}: YAML parse error: {e}")
            continue

        for repo_entry in cfg.get("repos", []):
            repo_url = repo_entry.get("repo", "")
            if repo_url != "https://github.com/cloud-gov/caulking":
                continue
            for h in repo_entry.get("hooks", []):
                hid = h.get("id")
                if hid not in hook_map:
                    errors.append(f"{cfg_path.name}: unknown caulking hook id '{hid}'")
                    continue
                hdef = hook_map[hid]
                if hdef.get("language") in {"system", "unsupported"}:
                    exe = str(hdef.get("entry", "")).split()[0]
                    if exe not in available_bins:
                        errors.append(
                            f"{cfg_path.name}: hook '{hid}' requires '{exe}' not covered by "
                            f"declared profiles {declared_profiles}"
                        )
    return errors


def main() -> None:
    """Run validation and exit with appropriate code."""
    errors, hook_count = validate_hooks()

    if errors:
        print("Validation errors:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        sys.exit(1)

    print(f"✅ Validated {hook_count} hooks successfully")
    sys.exit(0)


if __name__ == "__main__":
    main()
