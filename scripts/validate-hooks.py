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

        if (path.parent / "starter-configs").is_dir():
            has_selector = any(
                k in hook for k in ("types", "types_or", "files", "always_run")
            ) or hook.get("pass_filenames") is False
            if not has_selector:
                errors.append(
                    f"{hook_id}: missing file selector (types, types_or, files, always_run, or pass_filenames: false)"
                )
            repo_wide_markers = (
                " -d .",
                " -r .",
                " ./...",
                "scan source",
                "dir:.",
                "bundler-audit check",
                "npm audit",
                "yarn audit",
                "pnpm audit",
            )
            if any(m in entry for m in repo_wide_markers) and hook.get("pass_filenames") is not False:
                errors.append(
                    f"{hook_id}: repo-wide entry '{entry}' must set pass_filenames: false"
                )

    if (path.parent / "starter-configs").is_dir() and (path.parent / "brewfiles").is_dir():
        errors.extend(validate_starter_configs(path.parent, hooks))

    return errors, hook_count


FORMULA_PROFILE: dict[str, str] = {
    "gitleaks": "baseline",
    "prek": "baseline",
    "bash": "baseline",
    "shellcheck": "shell",
    "shfmt": "shell",
    "hadolint": "container",
    "ruff": "python",
    "mypy": "python",
    "pyright": "python",
    "bandit": "python",
    "pip-audit": "python",
    "go": "go",
    "golangci-lint": "go",
    "gosec": "go",
    "govulncheck": "go",
    "node": "javascript",
    "ruby": "ruby",
    "rubocop": "ruby",
    "opentofu": "opentofu",
    "terraform": "terraform",
    "tflint": "opentofu",
    "yamllint": "docs",
    "yamlfmt": "docs",
    "actionlint": "docs",
    "zizmor": "docs",
    "markdownlint-cli": "docs",
    "semgrep": "security",
    "osv-scanner": "security",
    "syft": "security",
    "grype": "security",
    "checkov": "security",
}

AMBIENT_SYSTEM_HOOKS: set[str] = {"check-yaml", "check-json"}

HOOK_FORMULAE: dict[str, set[str]] = {
    "shellcheck": {"shellcheck"},
    "shfmt": {"shfmt"},
    "shfmt-check": {"shfmt"},
    "bash-syntax": {"bash"},
    "hadolint": {"hadolint"},
    "ruff-check": {"ruff"},
    "ruff-format": {"ruff"},
    "ruff-format-check": {"ruff"},
    "mypy": {"mypy"},
    "pyright": {"pyright"},
    "bandit": {"bandit"},
    "pip-audit": {"pip-audit"},
    "go-fmt": {"go"},
    "go-vet": {"go"},
    "golangci-lint": {"golangci-lint"},
    "gosec": {"gosec"},
    "govulncheck": {"govulncheck"},
    "eslint": {"node"},
    "eslint-check": {"node"},
    "prettier": {"node"},
    "prettier-check": {"node"},
    "tsc": {"node"},
    "biome-check": {"node"},
    "biome-ci": {"node"},
    "npm-audit": {"node"},
    "yarn-audit": {"node"},
    "pnpm-audit": {"node"},
    "retire-js": {"node"},
    "ruby-check": {"ruby"},
    "rubocop": {"ruby", "rubocop"},
    "rubocop-check": {"ruby", "rubocop"},
    "bundle-audit": {"ruby"},
    "tofu-fmt": {"opentofu"},
    "tofu-validate": {"opentofu"},
    "terraform-fmt": {"terraform"},
    "terraform-validate": {"terraform"},
    "tflint": {"tflint"},
    "checkov": {"checkov"},
    "yamllint": {"yamllint"},
    "yamlfmt": {"yamlfmt"},
    "yamlfmt-check": {"yamlfmt"},
    "actionlint": {"actionlint"},
    "zizmor": {"zizmor"},
    "markdownlint": {"markdownlint-cli"},
    "markdownlint-check": {"markdownlint-cli"},
    "semgrep": {"semgrep"},
    "semgrep-ci": {"semgrep"},
    "osv-scanner": {"osv-scanner"},
    "osv-scanner-lockfile": {"osv-scanner"},
    "syft": {"syft"},
    "grype": {"grype"},
    "grype-sbom": {"grype"},
}


def validate_starter_configs(root: Path, hooks: list[dict]) -> list[str]:
    """Validate starter-configs/*.yaml against .pre-commit-hooks.yaml and brewfiles/."""
    errors: list[str] = []
    hook_map = {h["id"]: h for h in hooks if isinstance(h, dict) and "id" in h}
    starter_files = sorted((root / "starter-configs").glob("*.pre-commit-config.yaml"))
    if not starter_files:
        return ["No starter-configs/*.pre-commit-config.yaml files found"]

    toolchain_path = root / "scripts" / "toolchain.sh"
    toolchain_text = (
        toolchain_path.read_text(encoding="utf-8") if toolchain_path.is_file() else ""
    )

    for hid, hdef in hook_map.items():
        if hdef.get("language") in {"system", "unsupported"} and hid not in AMBIENT_SYSTEM_HOOKS:
            if hid not in HOOK_FORMULAE:
                errors.append(
                    f"{hid}: system/unsupported hook missing from HOOK_FORMULAE mapping"
                )
            else:
                for formula in HOOK_FORMULAE[hid]:
                    prof = FORMULA_PROFILE.get(formula)
                    if not prof:
                        errors.append(
                            f"{hid}: formula '{formula}' missing from FORMULA_PROFILE"
                        )
                    elif not (root / "brewfiles" / f"{prof}.Brewfile").is_file():
                        errors.append(
                            f"{hid}: formula '{formula}' profile '{prof}.Brewfile' missing"
                        )
            if toolchain_text and hid not in toolchain_text:
                errors.append(
                    f"{hid}: system/unsupported hook missing from scripts/toolchain.sh"
                )

    for cfg_path in starter_files:
        text = cfg_path.read_text(encoding="utf-8")
        if ".caulking-profiles" in text:
            errors.append(
                f"{cfg_path.name}: contains deprecated .caulking-profiles reference"
            )

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
                if hdef.get("language") in {"system", "unsupported"} and hid not in AMBIENT_SYSTEM_HOOKS:
                    formulae = HOOK_FORMULAE.get(hid, set())
                    if not formulae:
                        errors.append(
                            f"{cfg_path.name}: hook '{hid}' has no Homebrew formula mapping"
                        )
                    for formula in formulae:
                        prof = FORMULA_PROFILE.get(formula, "")
                        bf = root / "brewfiles" / f"{prof}.Brewfile"
                        if not prof or not bf.is_file():
                            errors.append(
                                f"{cfg_path.name}: hook '{hid}' formula '{formula}' "
                                f"not covered by brewfiles/{prof}.Brewfile"
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
