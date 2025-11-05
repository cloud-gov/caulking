from __future__ import annotations

from pathlib import Path

from caulking.config import CaulkingConfig


def test_default_config_loads(tmp_path: Path) -> None:
    # With no .caulking.yml, we should get defaults without crashing.
    cfg = CaulkingConfig.load(tmp_path / ".caulking.yml")
    assert cfg.enable.gitleaks is True
    assert cfg.enable.detect_secrets is True
