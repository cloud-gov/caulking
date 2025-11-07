from __future__ import annotations

import os
import shutil
import subprocess  # nosec B404
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

OK = "OK"
WARN = "WARN"
FAIL = "FAIL"


@dataclass
class Check:
    name: str
    status: str
    note: str


def _which(name: str) -> str | None:
    p = shutil.which(name)
    return str(Path(p).resolve()) if p else None


def _run(argv: Sequence[str]) -> tuple[int, str]:
    try:
        rc = subprocess.run(  # nosec B603 - fixed argv; shell disabled  # noqa: S603
            list(argv), check=False, capture_output=True, text=True
        )
        out = (rc.stdout or rc.stderr or "").strip()
        return rc.returncode, out
    except Exception as e:  # pragma: no cover
        return 1, repr(e)


def preflight(repo_root: Path) -> list[Check]:
    checks: list[Check] = []

    # Git
    git = _which("git")
    if not git:
        checks.append(Check("git", FAIL, "git not found in PATH"))
    else:
        rc, out = _run([git, "--version"])
        checks.append(Check("git", OK if rc == 0 else FAIL, out))

    # pre-commit
    pc = _which("pre-commit")
    if not pc:
        checks.append(Check("pre-commit", WARN, "pre-commit not installed"))
    else:
        rc, out = _run([pc, "--version"])
        checks.append(Check("pre-commit", OK if rc == 0 else FAIL, out))

    # gitleaks
    gl = _which("gitleaks")
    if not gl:
        checks.append(Check("gitleaks", WARN, "gitleaks not installed (brew install gitleaks)"))
    else:
        rc, out = _run([gl, "version"])
        checks.append(Check("gitleaks", OK if rc == 0 else FAIL, out))

    # PATH hygiene
    home_local = Path.home() / ".local" / "bin"
    path_ok = str(home_local) in os.environ.get("PATH", "")
    checks.append(
        Check(
            "PATH",
            OK if path_ok else WARN,
            f"{'has' if path_ok else 'missing'} {home_local} in PATH",
        )
    )

    # Git global hooksPath (advisory)
    rc, out = _run([git, "config", "--global", "core.hooksPath"]) if git else (1, "")
    if rc == 0 and out:
        checks.append(Check("core.hooksPath", OK, f"set to {out}"))
    else:
        checks.append(Check("core.hooksPath", WARN, "not set (advisory; smart-install can set)"))

    # Repo config presence
    cfg = repo_root / ".pre-commit-config.yaml"
    checks.append(
        Check(
            ".pre-commit-config.yaml",
            OK if cfg.exists() else WARN,
            "present" if cfg.exists() else "missing (smart-install will create/merge)",
        )
    )

    # gitleaks config presence
    gl_cfg = repo_root / "rules" / "gitleaks.toml"
    checks.append(
        Check(
            "rules/gitleaks.toml",
            OK if gl_cfg.exists() else WARN,
            "present" if gl_cfg.exists() else "missing (recommended for safer excludes)",
        )
    )

    return checks


def format_preflight(checks: list[Check]) -> str:
    lines = ["Preflight checks", "----------------"]
    for c in checks:
        badge = {"OK": "✔", "WARN": "▲", "FAIL": "✖"}.get(c.status, "?")
        lines.append(f"{badge} {c.name}: {c.status} — {c.note}")
    return "\n".join(lines)
