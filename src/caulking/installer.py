from __future__ import annotations

import json
import os
import shutil
import subprocess  # nosec B404
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Literal

import yaml

# ---------------------------
# Secrets (gitleaks + fallback)
# ---------------------------

SECRETS_BLOCK_GITLEAKS = {
    "repo": "https://github.com/zricethezav/gitleaks",
    "rev": "v8.18.4",
    "hooks": [
        {
            "id": "gitleaks",
            "args": [
                "detect",
                "--no-git",
                "--redact",
                "--report-format",
                "sarif",
                "--report-path",
                "artifacts/gitleaks.sarif",
                "--config",
                "rules/gitleaks.toml",
            ],
        }
    ],
}

SECRETS_BLOCK_DETECT_SECRETS = {
    "repo": "https://github.com/Yelp/detect-secrets",
    "rev": "v1.5.0",
    "hooks": [{"id": "detect-secrets", "args": ["--baseline", ".secrets.baseline"]}],
}

# ---------------------------
# Language/tool blocks (optional; guarded at runtime)
# ---------------------------

PYTHON_BLOCK = {
    "repo": "https://github.com/astral-sh/ruff-pre-commit",
    "rev": "v0.6.9",
    "hooks": [{"id": "ruff"}, {"id": "ruff-format"}],
}
BANDIT_BLOCK = {
    "repo": "https://github.com/PyCQA/bandit",
    "rev": "1.7.10",
    "hooks": [{"id": "bandit", "args": ["-q", "-c", "pyproject.toml", "-r", "src"]}],
}

PRECOMMIT_BASICS = {
    "repo": "https://github.com/pre-commit/pre-commit-hooks",
    "rev": "v4.6.0",
    "hooks": [
        {"id": "check-yaml"},
        {"id": "check-json"},
        {"id": "end-of-file-fixer"},
        {"id": "trailing-whitespace"},
        {"id": "mixed-line-ending"},
        {"id": "check-merge-conflict"},
    ],
}

NODE_BRIDGE_BLOCK = {
    "repo": "local",
    "hooks": [
        {
            "id": "run-node-bridge-husky",
            "name": "Node husky -> pre-commit bridge",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": [
                "-c",
                (
                    "command -v pre-commit >/dev/null && "
                    "pre-commit run --hook-stage=pre-commit || true"
                ),
            ],
        }
    ],
}

GO_BLOCK = {
    "repo": "local",
    "hooks": [
        {
            "id": "golangci-lint",
            "name": "golangci-lint",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": [
                "-c",
                "command -v golangci-lint >/dev/null && golangci-lint run ./... || true",
            ],
        },
        {
            "id": "gofmt",
            "name": "gofmt -s (check)",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": [
                "-c",
                (
                    "command -v go >/dev/null && "
                    "test -z \"$(gofmt -l .)\" || (gofmt -l .; exit 1)"
                ),
            ],
        },
    ],
}

RUST_BLOCK = {
    "repo": "local",
    "hooks": [
        {
            "id": "cargo-fmt-check",
            "name": "cargo fmt --check",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": ["-c", "command -v cargo >/dev/null && cargo fmt -- --check || true"],
        },
        {
            "id": "cargo-clippy",
            "name": "cargo clippy",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": ["-c", "command -v cargo >/dev/null && cargo clippy -- -D warnings || true"],
        },
    ],
}

JAVA_BLOCK = {
    "repo": "local",
    "hooks": [
        {
            "id": "maven-verify",
            "name": "mvn -q -DskipTests verify (if Maven present)",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": ["-c", "command -v mvn >/dev/null && mvn -q -DskipTests verify || true"],
        },
        {
            "id": "gradle-check",
            "name": "gradle build -x test (if Gradle present)",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": ["-c", "command -v gradle >/dev/null && gradle build -x test || true"],
        },
    ],
}

RUBY_BLOCK = {
    "repo": "local",
    "hooks": [
        {
            "id": "rubocop",
            "name": "rubocop (if present)",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": ["-c", "command -v rubocop >/dev/null && rubocop || true"],
        }
    ],
}

PHP_BLOCK = {
    "repo": "local",
    "hooks": [
        {
            "id": "php-lint",
            "name": "php -l on PHP files",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": [
                "-c",
                (
                    "command -v php >/dev/null && "
                    "files=$(git ls-files '*.php'); "
                    "[ -z \"$files\" ] || (for f in $files; do php -l \"$f\" || exit 1; done)"
                ),
            ],
        }
    ],
}

DOTNET_BLOCK = {
    "repo": "local",
    "hooks": [
        {
            "id": "dotnet-format",
            "name": "dotnet format --verify-no-changes",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": [
                "-c",
                "command -v dotnet >/dev/null && dotnet format --verify-no-changes || true",
            ],
        }
    ],
}

TERRAFORM_BLOCK = {
    "repo": "local",
    "hooks": [
        {
            "id": "tflint",
            "name": "tflint",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": ["-c", "command -v tflint >/dev/null && tflint --format=compact || true"],
        },
        {
            "id": "terraform-fmt",
            "name": "terraform fmt -check -recursive",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": [
                "-c",
                "command -v terraform >/dev/null && terraform fmt -check -recursive || true",
            ],
        },
    ],
}

DOCKER_BLOCK = {
    "repo": "local",
    "hooks": [
        {
            "id": "hadolint",
            "name": "hadolint",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": [
                "-c",
                (
                    "command -v hadolint >/dev/null && "
                    "hadolint $(git ls-files '*Dockerfile*') || true"
                ),
            ],
        }
    ],
}

SHELL_BLOCK = {
    "repo": "local",
    "hooks": [
        {
            "id": "shellcheck",
            "name": "shellcheck",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": [
                "-c",
                (
                    "command -v shellcheck >/dev/null && "
                    "shellcheck -S warning -x $(git ls-files '*.sh') || true"
                ),
            ],
        }
    ],
}

WEB_BLOCKS = {
    "repo": "local",
    "hooks": [
        {
            "id": "eslint",
            "name": "eslint (if present)",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": ["-c", "command -v eslint >/dev/null && eslint . || true"],
        },
        {
            "id": "prettier-check",
            "name": "prettier --check (if present)",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": ["-c", "command -v prettier >/dev/null && prettier --check . || true"],
        },
        {
            "id": "stylelint",
            "name": "stylelint (if present)",
            "entry": "bash",
            "language": "system",
            "pass_filenames": False,
            "args": ["-C", "command -v stylelint >/dev/null && stylelint \"**/*.css\" || true"],
        },
    ],
}

# ---------------------------
# Template copy (rules + helper script)
# ---------------------------

TEMPLATES_DIR = Path(__file__).resolve().parents[2] / "templates" / "precommit"


@dataclass(frozen=True)
class CopySpec:
    src: Path
    dst: Path
    make_executable: bool = False


VERBATIM_FILES: list[CopySpec] = [
    CopySpec(TEMPLATES_DIR / "gitleaks.toml", Path("rules/gitleaks.toml")),
    CopySpec(
        TEMPLATES_DIR / "detect_secrets_advisory_template.py",
        Path("scripts/detect_secrets_advisory.py"),
        make_executable=True,
    ),
]

# ---------------------------
# Detection
# ---------------------------


def _exists_any(root: Path, pattern: str) -> bool:
    try:
        next(root.rglob(pattern))
        return True
    except StopIteration:
        return False


@dataclass(frozen=True)
class Detection:
    python: bool
    node: bool
    go: bool
    rust: bool
    java: bool
    ruby: bool
    php: bool
    dotnet: bool
    terraform: bool
    docker: bool
    has_shell: bool


def detect_repo(path: Path) -> Detection:
    p = path.resolve()
    return Detection(
        python=(p.joinpath("pyproject.toml").exists() or p.joinpath("setup.cfg").exists()),
        node=p.joinpath("package.json").exists(),
        go=p.joinpath("go.mod").exists(),
        rust=p.joinpath("Cargo.toml").exists(),
        java=(p.joinpath("pom.xml").exists() or _exists_any(p, "build.gradle*")),
        ruby=p.joinpath("Gemfile").exists(),
        php=p.joinpath("composer.json").exists() or _exists_any(p, "*.php"),
        dotnet=_exists_any(p, "*.sln") or _exists_any(p, "*.csproj"),
        terraform=_exists_any(p, "*.tf"),
        docker=(p.joinpath("Dockerfile").exists() or _exists_any(p, "*Dockerfile*")),
        has_shell=_exists_any(p, "*.sh"),
    )


# ---------------------------
# Merge logic
# ---------------------------


def _append_unique(cfg: dict[str, Any], block: dict[str, Any]) -> bool:
    repos = cfg.setdefault("repos", [])
    for existing in repos:
        if existing.get("repo") == block["repo"]:
            have_ids = {h.get("id") for h in existing.get("hooks", [])}
            new_hooks = [h for h in block.get("hooks", []) if h.get("id") not in have_ids]
            if new_hooks:
                existing.setdefault("hooks", []).extend(new_hooks)
                return True
            return False
    repos.append(block)
    return True


def read_precommit(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"repos": []}
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    return data if isinstance(data, dict) else {"repos": []}


def write_precommit(path: Path, cfg: dict[str, Any]) -> None:
    path.write_text(yaml.safe_dump(cfg, sort_keys=False), encoding="utf-8")


def plan_merge(
    current_cfg: dict[str, Any],
    *,
    python: bool,
    node: bool,
    go: bool,
    rust: bool,
    java: bool,
    ruby: bool,
    php: bool,
    dotnet: bool,
    terraform: bool,
    docker: bool,
    has_shell: bool,
) -> tuple[dict[str, Any], list[str]]:
    cfg = {**current_cfg}
    changes: list[str] = []

    # Always: secrets + basic hygiene hooks
    if _append_unique(cfg, SECRETS_BLOCK_GITLEAKS):
        changes.append("add: gitleaks (mandatory, safer excludes)")
    if _append_unique(cfg, SECRETS_BLOCK_DETECT_SECRETS):
        changes.append("add: detect-secrets baseline (fallback)")
    if _append_unique(cfg, PRECOMMIT_BASICS):
        changes.append("add: pre-commit basics (yaml/json/whitespace/etc.)")

    optionals: list[tuple[bool, dict[str, Any], str]] = [
        (python, PYTHON_BLOCK, "add: ruff + ruff-format"),
        (python, BANDIT_BLOCK, "add: bandit"),
        (node, NODE_BRIDGE_BLOCK, "add: node husky bridge -> pre-commit"),
        (node, WEB_BLOCKS, "add: eslint/prettier/stylelint (if present)"),
        (go, GO_BLOCK, "add: golangci-lint + gofmt"),
        (rust, RUST_BLOCK, "add: cargo fmt/clippy"),
        (java, JAVA_BLOCK, "add: maven/gradle checks (if present)"),
        (ruby, RUBY_BLOCK, "add: rubocop (if present)"),
        (php, PHP_BLOCK, "add: php -l (lint)"),
        (dotnet, DOTNET_BLOCK, "add: dotnet format"),
        (terraform, TERRAFORM_BLOCK, "add: tflint + terraform fmt"),
        (docker, DOCKER_BLOCK, "add: hadolint (if present)"),
        (has_shell, SHELL_BLOCK, "add: shellcheck"),
    ]
    for cond, block, msg in optionals:
        if cond and _append_unique(cfg, block):
            changes.append(msg)

    return cfg, changes


# ---------------------------
# Planning / Applying + Logs
# ---------------------------


@dataclass
class PlannedAction:
    kind: str
    description: str
    meta: dict[str, Any]


def _now_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")


def _which(bin_name: str) -> str | None:
    p = shutil.which(bin_name)
    return str(Path(p).resolve()) if p else None


def _git_config_set_global(key: str, value: str) -> tuple[int, str]:
    git_bin = _which("git")
    if not git_bin:
        return (127, "git not found")
    rc = subprocess.run(  # noqa: S603  # nosec B603
        [git_bin, "config", "--global", key, value],
        check=False,
        capture_output=True,
        text=True,
    )
    out = (rc.stdout or rc.stderr or "").strip()
    return (rc.returncode, out)


def _precommit_install(cwd: Path) -> tuple[int, str]:
    pc = _which("pre-commit")
    if not pc:
        return (127, "pre-commit not found")
    rc = subprocess.run(  # noqa: S603  # nosec B603
        [pc, "install", "-t", "pre-commit", "-t", "pre-push"],
        cwd=str(cwd),
        check=False,
        text=True,
        capture_output=True,
    )
    out = (rc.stdout or rc.stderr or "").strip()
    return (rc.returncode, out)


def _copy_file(src: Path, dst: Path, make_executable: bool) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    if make_executable:
        mode = dst.stat().st_mode
        dst.chmod(mode | 0o111)


@dataclass
class Logger:
    path: Path

    def write(self, msg: str) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        ts = datetime.now(timezone.utc).isoformat()
        user = os.environ.get("USER") or os.environ.get("USERNAME") or "unknown"
        line = f"{ts} {user} {msg}\n"
        with self.path.open("a", encoding="utf-8") as f:
            f.write(line)


def _ensure_path_rc_lines(rc: Path, backup_dir: Path, ts: str) -> PlannedAction | None:
    if not rc.exists():
        return None
    line = 'export PATH="$HOME/.local/bin:$PATH"'
    text = rc.read_text(encoding="utf-8")
    if line in text:
        return None
    backup_dir.mkdir(parents=True, exist_ok=True)
    dest = backup_dir / rc.name
    dest.write_text(text, encoding="utf-8")
    appended = f"\n# Added by caulking smart-install on {ts}\n{line}\n"
    return PlannedAction(
        kind="rc-append",
        description=f"Append PATH to {rc}",
        meta={"rc_path": str(rc), "backup_to": str(dest), "content": appended},
    )


def _apply_rc_append(action: PlannedAction) -> None:
    rc_path = Path(action.meta["rc_path"])
    rc_path.write_text(
        rc_path.read_text(encoding="utf-8") + action.meta["content"],
        encoding="utf-8",
    )


# expose formatter for CLI import-at-top
def _format_plan(actions: Iterable[PlannedAction]) -> str:
    rows = []
    for a in actions:
        rows.append(f"- [{a.kind}] {a.description}")
        if a.kind == "rc-append":
            rows.append(f"    backup: {a.meta['backup_to']}")
        if a.kind == "git-global":
            rows.append(f"    git config --global {a.meta['key']} {a.meta['value']}")
        if a.kind == "precommit-install":
            rows.append(f"    repo: {a.meta['repo']}")
        if a.kind == "merge-precommit":
            rows.append(f"    file: {a.meta['path']}")
            rows.append(f"    changes: {json.dumps(a.meta['changes'], indent=2)}")
        if a.kind == "write-file":
            rows.append(f"    src: {a.meta['src']}")
            rows.append(f"    dst: {a.meta['dst']}")
            if a.meta.get("executable"):
                rows.append("    chmod: +x")
    return "\n".join(rows)


GlobalMode = Literal["off", "advisory", "enforce"]


def plan_smart_install(
    repo_root: Path, *, global_mode: GlobalMode = "advisory"
) -> list[PlannedAction]:
    actions: list[PlannedAction] = []
    ts = _now_stamp()

    if not (repo_root / ".git").exists():
        actions.append(
            PlannedAction("warn", "Not a Git repository (no .git); some steps will be skipped.", {})
        )

    # rc edits
    rc_candidates = [
        Path.home() / ".zshrc",
        Path.home() / ".bashrc",
        Path.home() / ".bash_profile",
        Path.home() / ".profile",
    ]
    backup_dir = Path.home() / ".caulking-smart-install-backup" / ts
    for rc in rc_candidates:
        act = _ensure_path_rc_lines(rc, backup_dir, ts)
        if act:
            actions.append(act)

    # global hooks
    if global_mode in ("advisory", "enforce"):
        hooks_root = Path.home() / ".config" / "pre-commit"
        hooks_root.mkdir(parents=True, exist_ok=True)
        actions.append(
            PlannedAction(
                "git-global",
                f"Set core.hooksPath -> {hooks_root}",
                {"key": "core.hooksPath", "value": str(hooks_root)},
            )
        )

    # copy template files (rules + advisory helper)
    for spec in VERBATIM_FILES:
        actions.append(
            PlannedAction(
                "write-file",
                f"Write {spec.dst} from template",
                {
                    "src": str(spec.src),
                    "dst": str((repo_root / spec.dst).resolve()),
                    "executable": spec.make_executable,
                },
            )
        )

    # merge pre-commit config
    cfg_path = repo_root / ".pre-commit-config.yaml"
    current = read_precommit(cfg_path)
    det = detect_repo(repo_root)
    merged, changes = plan_merge(
        current,
        python=det.python,
        node=det.node,
        go=det.go,
        rust=det.rust,
        java=det.java,
        ruby=det.ruby,
        php=det.php,
        dotnet=det.dotnet,
        terraform=det.terraform,
        docker=det.docker,
        has_shell=det.has_shell,
    )
    actions.append(
        PlannedAction(
            "merge-precommit",
            "Merge mandatory secrets + optional linters into .pre-commit-config.yaml",
            {"path": str(cfg_path), "merged": merged, "changes": changes},
        )
    )

    # install hooks
    actions.append(
        PlannedAction(
            "precommit-install",
            "Install repo hooks (pre-commit/pre-push)",
            {"repo": str(repo_root)},
        )
    )

    # hint if gitleaks missing
    if _which("gitleaks") is None:
        actions.append(PlannedAction("hint", "gitleaks not found; e.g., brew install gitleaks", {}))

    return actions


def apply_smart_install(
    actions: Iterable[PlannedAction],
    *,
    log_path: Path,
) -> list[tuple[str, int, str]]:
    logger = Logger(log_path)
    results: list[tuple[str, int, str]] = []
    for act in actions:
        if act.kind == "rc-append":
            _apply_rc_append(act)
            rc_path = act.meta["rc_path"]
            backup_to = act.meta["backup_to"]
            note = f"Backed up {rc_path} -> {backup_to}; appended PATH"
            results.append(("rc-append", 0, note))
            logger.write(f"rc-append {note}")
        elif act.kind == "git-global":
            rc, out = _git_config_set_global(act.meta["key"], act.meta["value"])
            results.append(("git-global", rc, out))
            logger.write(
                f"git-global key={act.meta['key']} value={act.meta['value']} rc={rc} out={out}"
            )
        elif act.kind == "write-file":
            src = Path(act.meta["src"])
            dst = Path(act.meta["dst"])
            exec_flag = bool(act.meta.get("executable", False))
            _copy_file(src, dst, exec_flag)
            msg = f"Wrote {dst} from {src}" + (" (+x)" if exec_flag else "")
            results.append(("write-file", 0, msg))
            logger.write(f"write-file {msg}")
        elif act.kind == "merge-precommit":
            cfg_path = Path(act.meta["path"])
            write_precommit(cfg_path, act.meta["merged"])
            results.append(("merge-precommit", 0, f"Wrote {cfg_path}"))
            logger.write(f"merge-precommit wrote={cfg_path}")
        elif act.kind == "precommit-install":
            rc, out = _precommit_install(Path(act.meta["repo"]))
            results.append(("precommit-install", rc, out))
            logger.write(f"precommit-install repo={act.meta['repo']} rc={rc} out={out}")
        else:
            results.append((act.kind, 0, act.description))
            logger.write(f"{act.kind} {act.description}")
    return results
