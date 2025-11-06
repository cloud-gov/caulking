from __future__ import annotations

from .detector import Detection, detect_repo
from .installer import plan_merge, write_precommit

__all__ = [
    "Detection",
    "detect_repo",
    "plan_merge",
    "write_precommit",
]
