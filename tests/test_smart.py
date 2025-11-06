from __future__ import annotations

from pathlib import Path

import yaml

from caulking.installer import plan_merge


def test_plan_always_includes_secrets(tmp_path: Path) -> None:
    merged_cfg, changes = plan_merge(
        {"repos": []},
        python=False,
        node=False,
        go=False,
        terraform=False,
        docker=False,
        has_shell=False,
    )
    assert any("gitleaks" in c for c in changes)
    assert any("detect-secrets" in c for c in changes)

    pc = tmp_path / ".pre-commit-config.yaml"
    pc.write_text(yaml.safe_dump(merged_cfg, sort_keys=False), encoding="utf-8")
    data = yaml.safe_load(pc.read_text(encoding="utf-8"))
    assert isinstance(data.get("repos"), list)


def test_python_adds_ruff_and_bandit(tmp_path: Path) -> None:
    _merged_cfg, changes = plan_merge(
        {"repos": []},
        python=True,
        node=False,
        go=False,
        terraform=False,
        docker=False,
        has_shell=False,
    )
    assert any("ruff" in c for c in changes)
    assert any("bandit" in c for c in changes)
