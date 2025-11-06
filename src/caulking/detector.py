from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Detection:
    python: bool = False
    node: bool = False
    go: bool = False
    terraform: bool = False
    docker: bool = False
    has_shell: bool = False  # renamed to avoid Bandit B604 false positive


def _exists_any(root: Path, pattern: str) -> bool:
    """Return True if any file under root matches the glob pattern."""
    try:
        next(root.rglob(pattern))
        return True
    except StopIteration:
        return False


def detect_repo(root: Path = Path(".")) -> Detection:
    p = root.resolve()
    return Detection(
        python=(p.joinpath("pyproject.toml").exists() or p.joinpath("requirements.txt").exists()),
        node=p.joinpath("package.json").exists(),
        go=p.joinpath("go.mod").exists(),
        terraform=_exists_any(p, "*.tf"),
        docker=p.joinpath("Dockerfile").exists(),
        # NOTE: presence signal for adding a shellcheck hook if available.
        has_shell=_exists_any(p, "*.sh"),
    )


__all__ = ["Detection", "detect_repo"]
