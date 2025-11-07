from __future__ import annotations

from pathlib import Path
from typing import Any

from caulking.installer import plan_merge


def test_plan_merge_minimal(tmp_path: Path) -> None:
    cfg: dict[str, Any] = {"repos": []}
    merged, _changes = plan_merge(
        cfg,
        python=False,
        node=False,
        go=False,
        rust=False,
        java=False,
        ruby=False,
        php=False,
        dotnet=False,
        terraform=False,
        docker=False,
        has_shell=False,
    )
    assert "repos" in merged
    # Should at least include a secrets scanner by default
    assert any("gitleaks" in str(entry) for entry in merged["repos"])


def test_plan_merge_python(tmp_path: Path) -> None:
    cfg: dict[str, Any] = {"repos": []}
    merged, _changes = plan_merge(
        cfg,
        python=True,
        node=False,
        go=False,
        rust=False,
        java=False,
        ruby=False,
        php=False,
        dotnet=False,
        terraform=False,
        docker=False,
        has_shell=False,
    )
    # ruff hooks should be present for python=True
    assert any(
        isinstance(r, dict) and str(r.get("repo", "")).endswith("ruff-pre-commit")
        for r in merged["repos"]
    )
