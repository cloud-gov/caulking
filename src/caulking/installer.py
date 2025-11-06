from __future__ import annotations

import io
from pathlib import Path
from typing import Any

import yaml

# --- Mandatory, always-on secrets scanning blocks (blocking) -------------------

MANDATORY_SECRETS_REPO: dict[str, Any] = {
    "repo": "https://github.com/gitleaks/gitleaks",
    "rev": "v8.29.0",
    "hooks": [
        {
            "id": "gitleaks",
            "name": "gitleaks (cloud-gov rules)",
            "args": [
                "--no-banner",
                "--no-color",
                "--log-level=error",
                "--redact",
                "--config=rules/gitleaks.toml",
            ],
            "pass_filenames": False,
            "stages": ["pre-commit"],
            "exclude": "(?x)\n^tests/corpus/.*|^\\.refactor-backup/",
            "entry": "gitleaks git --pre-commit",
        }
    ],
}

DETECT_SECRETS_LOCAL: dict[str, Any] = {
    "repo": "local",
    "hooks": [
        {
            "id": "detect-secrets",
            "name": "detect-secrets (baseline)",
            "entry": "detect-secrets-hook",
            "language": "system",
            "pass_filenames": False,
            "args": ["--baseline", "rules/detect-secrets.baseline"],
            "exclude": "(?x)\n^tests/corpus/.*|^\\.refactor-backup/",
        }
    ],
}

# --- Ecosystem hook blocks (added if that ecosystem is detected/enabled) ------

PYTHON_BLOCK: dict[str, Any] = {
    "repo": "https://github.com/astral-sh/ruff-pre-commit",
    "rev": "v0.7.1",
    "hooks": [
        {"id": "ruff", "args": ["--fix"]},
        {"id": "ruff-format"},
    ],
}

BANDIT_BLOCK: dict[str, Any] = {
    "repo": "https://github.com/PyCQA/bandit",
    "rev": "1.7.10",
    "hooks": [
        {"id": "bandit", "args": ["-q", "-c", "pyproject.toml", "-r", "src"]},
    ],
}

# Minimal stubs for non-Python ecosystems — we *don't* inject eslint configs, just a bridge.
_NODE_BRIDGE_CMD = (
    "command -v pre-commit >/dev/null && pre-commit run --hook-stage=pre-commit || true"
)
NODE_BRIDGE_BLOCK: dict[str, Any] = {
    "repo": "local",
    "hooks": [
        {
            "id": "node-husky-bridge",
            "name": "husky bridge -> run pre-commit",
            "entry": "bash",
            "language": "system",
            "args": ["-c", _NODE_BRIDGE_CMD],
        }
    ],
}

GO_BLOCK: dict[str, Any] = {
    "repo": "local",
    "hooks": [
        {
            "id": "golangci-lint",
            "name": "golangci-lint (if present)",
            "entry": "bash",
            "language": "system",
            "args": ["-c", "command -v golangci-lint >/dev/null && golangci-lint run || true"],
        }
    ],
}

TERRAFORM_BLOCK: dict[str, Any] = {
    "repo": "local",
    "hooks": [
        {
            "id": "tflint",
            "name": "tflint (if present)",
            "entry": "bash",
            "language": "system",
            "args": ["-c", "command -v tflint >/dev/null && tflint --format compact || true"],
        }
    ],
}

_SHELLCHECK_CMD = (
    "command -v shellcheck >/dev/null && "
    "files=$(git ls-files '*.sh') && "
    '[ -n "$files" ] && shellcheck -S warning -x $files || true'
)
SHELL_BLOCK: dict[str, Any] = {
    "repo": "local",
    "hooks": [
        {
            "id": "shellcheck",
            "name": "shellcheck (if present)",
            "entry": "bash",
            "language": "system",
            "args": ["-c", _SHELLCHECK_CMD],
        }
    ],
}

# Hadolint for Dockerfiles
_HADOLINT_CMD = (
    "command -v hadolint >/dev/null && "
    "files=$(git ls-files 'Dockerfile*') && "
    '[ -n "$files" ] && hadolint $files || true'
)
DOCKER_BLOCK: dict[str, Any] = {
    "repo": "local",
    "hooks": [
        {
            "id": "hadolint",
            "name": "hadolint (if present)",
            "entry": "bash",
            "language": "system",
            "args": ["-c", _HADOLINT_CMD],
        }
    ],
}


# --- helpers -------------------------------------------------------------------


def _load_precommit(path: Path) -> dict[str, Any]:
    if path.exists():
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        if not isinstance(data, dict):
            raise SystemExit("pre-commit config must be a mapping")
        return data
    return {
        "ci": {"autofix_prs": False},
        "default_install_hook_types": ["pre-commit", "pre-push"],
        "repos": [],
    }


def _has_repo(cfg: dict[str, Any], repo_url: str) -> bool:
    return any(
        isinstance(r, dict) and str(r.get("repo", "")) == repo_url for r in (cfg.get("repos") or [])
    )


def _append_unique(cfg: dict[str, Any], repo_block: dict[str, Any]) -> bool:
    if _has_repo(cfg, repo_block.get("repo", "")):
        return False
    cfg.setdefault("repos", []).append(repo_block)
    return True


# --- public API used by tests/CLI ----------------------------------------------


def plan_merge(  # noqa: PLR0913
    current_cfg: dict[str, Any],
    *,
    python: bool,
    node: bool,
    go: bool,
    terraform: bool,
    docker: bool,
    has_shell: bool,
) -> tuple[dict[str, Any], list[str]]:
    """
    Merge mandatory secrets hooks and ecosystem-specific hooks into an existing
    pre-commit config without clobbering unrelated content. Returns (merged_cfg, changes).
    """
    cfg = current_cfg.copy() if current_cfg else _load_precommit(Path("/dev/null"))
    cfg.setdefault("repos", [])

    changes: list[str] = []

    # Secrets are mandatory and blocking.
    if _append_unique(cfg, MANDATORY_SECRETS_REPO):
        changes.append("add: gitleaks (mandatory)")
    if _append_unique(cfg, DETECT_SECRETS_LOCAL):
        changes.append("add: detect-secrets (baseline)")

    if python and _append_unique(cfg, PYTHON_BLOCK):
        changes.append("add: ruff (+format)")
    if python and _append_unique(cfg, BANDIT_BLOCK):
        changes.append("add: bandit")

    if node and _append_unique(cfg, NODE_BRIDGE_BLOCK):
        changes.append("add: node husky bridge -> pre-commit")

    if go and _append_unique(cfg, GO_BLOCK):
        changes.append("add: golangci-lint (if present)")

    if terraform and _append_unique(cfg, TERRAFORM_BLOCK):
        changes.append("add: tflint (if present)")

    if docker and _append_unique(cfg, DOCKER_BLOCK):
        changes.append("add: hadolint (if present)")

    if has_shell and _append_unique(cfg, SHELL_BLOCK):
        changes.append("add: shellcheck (if present)")

    return cfg, changes


def write_precommit(path: Path, cfg: dict[str, Any]) -> None:
    out = io.StringIO()
    yaml.safe_dump(cfg, out, sort_keys=False)
    path.write_text(out.getvalue(), encoding="utf-8")


__all__ = ["plan_merge", "write_precommit"]
