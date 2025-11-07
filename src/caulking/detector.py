from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


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
    terraform: bool
    docker: bool
    has_shell: bool  # named to avoid Bandit B604 false-positives


def detect_repo(path: Path) -> Detection:
    p = path.resolve()
    return Detection(
        python=(p.joinpath("pyproject.toml").exists() or p.joinpath("setup.cfg").exists()),
        node=(p.joinpath("package.json").exists()),
        go=(p.joinpath("go.mod").exists()),
        terraform=_exists_any(p, "*.tf"),
        docker=(p.joinpath("Dockerfile").exists()),
        # Presence signal only, used to decide whether to add shellcheck hook optionally.
        has_shell=_exists_any(p, "*.sh"),  # nosec B604 - not shell=True; naming false positive
    )


__all__ = ["Detection", "detect_repo"]
