from __future__ import annotations

from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, Field, ValidationError

# NOTE (Standards): This schema aligns with your router intent:
# - CS:python / TS:pytest are implicit when python is enabled.
# - SEC:*  is enforced via mandatory secrets hooks everywhere.


Ecosystem = Literal["python", "node", "go", "terraform", "docker", "shell"]


class HookPack(BaseModel):
    # Minimal toggle surface; secrets always enforced.
    ruff: bool | None = None  # python
    mypy: bool | None = None  # python
    bandit: bool | None = None  # python
    eslint: bool | None = None  # node (bridge-only; we never inject eslint rules)
    golangci_lint: bool | None = None  # go
    tflint: bool | None = None  # terraform
    hadolint: bool | None = None  # docker
    shellcheck: bool | None = None  # shell
    husky_bridge: bool | None = None  # node: run pre-commit via Husky if project uses it


class EcosystemBlock(BaseModel):
    enabled: bool = True
    hooks: HookPack = Field(default_factory=HookPack)


class CaulkingManifest(BaseModel):
    # Per your standards router, we keep it obvious.
    python: EcosystemBlock | None = Field(default_factory=EcosystemBlock)
    node: EcosystemBlock | None = None
    go: EcosystemBlock | None = None
    terraform: EcosystemBlock | None = None
    docker: EcosystemBlock | None = None
    shell: EcosystemBlock | None = None

    class Config:
        extra = "ignore"

    @staticmethod
    def load(path: Path = Path("caulking.yaml")) -> CaulkingManifest | None:
        if not path.exists():
            return None
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
            return CaulkingManifest(**data)
        except (yaml.YAMLError, ValidationError) as exc:  # pragma: no cover
            raise SystemExit(f"Invalid caulking.yaml: {exc}") from exc
