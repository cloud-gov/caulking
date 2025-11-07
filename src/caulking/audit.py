from __future__ import annotations

import shutil
import subprocess  # nosec B404
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, cast


def _which(bin_name: str) -> str | None:
    p = shutil.which(bin_name)
    return str(Path(p).resolve()) if p else None


def _global_precommit_path() -> str | None:
    git_bin = _which("git")
    if not git_bin:
        return None
    try:
        out = subprocess.check_output(  # nosec B603  # noqa: S603
            [git_bin, "config", "--global", "core.hooksPath"],
            text=True,
        )
        return out.strip() or None
    except Exception:
        return None


@dataclass(frozen=True)
class AuditResult:
    ok: bool
    details: dict[str, Any]
    report_text: str


def _has_gitleaks() -> tuple[bool, str | None, tuple[int, int, int] | None]:
    gl = _which("gitleaks")
    if not gl:
        return (False, None, None)
    try:
        out = subprocess.check_output([gl, "version"], text=True)  # nosec B603  # noqa: S603
        v = out.strip().lstrip("v")
        parts_raw = tuple(int(x) for x in v.split(".")[:3])
        parts: tuple[int, int, int] = cast(
            tuple[int, int, int],
            (*parts_raw, 0, 0, 0)[:3],
        )
        return (True, gl, parts)
    except Exception:
        return (True, gl, None)


def _probe_gitleaks_detects() -> bool:
    ok, gl_path, _ = _has_gitleaks()
    if not ok or not gl_path:
        return False

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        (tmp / "canary.txt").write_text(
            "AWS_SECRET_ACCESS_KEY=AKIA1234567890EXAMPLE\n",  # used to verify gitleaks is wired  # gitleaks:allow  # noqa: E501
            encoding="utf-8",
        )
        out_path = tmp / "out.sarif"
        rc = subprocess.run(  # nosec B603  # noqa: S603
            [
                gl_path,
                "detect",
                "--no-git",
                "--report-format",
                "sarif",
                "--report-path",
                str(out_path),
            ],
            cwd=str(tmp),
            check=False,
        ).returncode
        detected = rc == 1 or out_path.exists()
        return bool(detected)


def audit(strict: bool = False) -> AuditResult:
    """Quarterly audit: ensure global enforcement + gitleaks existence (+ optional signal test)."""
    details: dict[str, Any] = {}

    hooks_path = _global_precommit_path()
    details["system_enforcement"] = {
        "global_hooks_path": hooks_path or "",
        "enabled": bool(hooks_path),
        "hint": "Set with: git config --global core.hooksPath ~/.config/pre-commit",
    }

    has_gl, gl_bin, gl_ver = _has_gitleaks()
    details["gitleaks"] = {
        "present": has_gl,
        "path": gl_bin or "",
        "version": gl_ver or (),
    }

    signal_detected = _probe_gitleaks_detects() if has_gl else False
    details["signal_test"] = {"canary_detected": signal_detected}

    ok = bool(
        details["system_enforcement"]["enabled"]
        and has_gl
        and (signal_detected if strict else True)
    )

    se_enabled = details["system_enforcement"]["enabled"]
    lines = [
        "Caulking Audit Report",
        "======================",
        "- Global pre-commit enforcement: " + ("ENABLED" if se_enabled else "DISABLED"),
        "- gitleaks present: " + ("YES" if has_gl else "NO") + (f" ({gl_bin})" if gl_bin else ""),
        "- canary detection: "
        + ("PASS" if signal_detected else ("SKIP" if not has_gl else "FAIL")),
        "",
        "Recommendation:",
        "- If DISABLED, run: git config --global core.hooksPath ~/.config/pre-commit",
        "- Ensure gitleaks is installed (brew install gitleaks on macOS).",
    ]
    status = "PASS" if ok else "FAIL"
    lines.append(f"\nOverall: {status}")
    return AuditResult(ok=ok, details=details, report_text="\n".join(lines))
