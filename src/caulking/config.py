from __future__ import annotations

from pathlib import Path

import yaml
from pydantic import BaseModel, Field, ValidationError


class HygieneToggles(BaseModel):
    ruff: bool = True
    shellcheck: bool = False  # available in CI containers only by default
    markdownlint: bool = True
    yamllint: bool = True


class Enablement(BaseModel):
    gitleaks: bool = True
    detect_secrets: bool = True
    hygiene: HygieneToggles = Field(default_factory=HygieneToggles)


class ExcludeEntry(BaseModel):
    path: str
    reason: str | None = None


class CaulkingConfig(BaseModel):
    enable: Enablement = Field(default_factory=Enablement)
    excludes: list[ExcludeEntry] = Field(default_factory=list)

    @staticmethod
    def load(path: Path = Path(".caulking.yml")) -> CaulkingConfig:
        if not path.exists():
            return CaulkingConfig()
        try:
            data = yaml.safe_load(path.read_text()) or {}
            return CaulkingConfig(**data)
        except (yaml.YAMLError, ValidationError) as exc:  # pragma: no cover
            raise SystemExit(f"Invalid .caulking.yml: {exc}") from exc
