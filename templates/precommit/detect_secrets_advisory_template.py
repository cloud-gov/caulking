# mypy: ignore-errors
#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

# Template copy of the advisory helper. The installer copies this to scripts/
# as detect_secrets_advisory.py and marks it executable. We ignore this file in
# mypy to avoid any analysis churn in consuming repos.
BASELINE = Path(".secrets.baseline")


def main(argv: list[str]) -> int:
    dsh = shutil.which("detect-secrets-hook")
    if dsh is None:
        print("[detect-secrets] detect-secrets-hook not found; skipping (advisory).")
        return 0

    if not BASELINE.exists():
        print(
            "[detect-secrets] No .secrets.baseline found; skipping (advisory).\n"
            "  To enable: detect-secrets scan > .secrets.baseline && git add .secrets.baseline\n"
            "  Note: gitleaks already protects the repo."
        )
        return 0

    cmd = [dsh, "--baseline", str(BASELINE), *argv]
    try:
        # Fixed argv; shell disabled.
        return subprocess.run(cmd, check=False).returncode  # noqa: S603
    except OSError as exc:
        print(f"[detect-secrets] Failed to execute detect-secrets-hook: {exc}")
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
