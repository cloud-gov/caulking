from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import yaml


@dataclass(frozen=True)
class EnableFlags:
    gitleaks: bool = True
    detect_secrets: bool = True


@dataclass(frozen=True)
class CaulkingConfig:
    enable: EnableFlags

    @staticmethod
    def load(path: Path) -> CaulkingConfig:
        if not path.exists():
            return CaulkingConfig(enable=EnableFlags())
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        enable = data.get("enable", {}) if isinstance(data, dict) else {}
        return CaulkingConfig(
            enable=EnableFlags(
                gitleaks=bool(enable.get("gitleaks", True)),
                detect_secrets=bool(enable.get("detect_secrets", True)),
            )
        )
