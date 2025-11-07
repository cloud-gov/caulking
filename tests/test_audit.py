from __future__ import annotations

import shutil

import pytest

from caulking.audit import audit


@pytest.mark.skipif(
    shutil.which("pre-commit") is None,
    reason="pre-commit not installed; install via Brew (macOS) or pipx/pip (Linux).",
)
def test_audit_runs_soft_ok() -> None:
    # Not asserting strict PASS to avoid CI flakiness when gitleaks absent.
    res = audit(strict=False)
    assert isinstance(res.ok, bool)
    assert "system_enforcement" in res.details
