"""Check local release invariants without contacting GitHub or publishing."""

import json
import re
from pathlib import Path


def validate(root):
    version = (root / "VERSION").read_text().strip()
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", version):
        raise ValueError("VERSION must contain only a stable SemVer version")
    manifest = json.loads((root / ".release-please-manifest.json").read_text())
    if manifest != {".": version}:
        raise ValueError("VERSION and release manifest must agree")
    config = json.loads((root / "release-please-config.json").read_text())
    if set(config["packages"]) != {"."}:
        raise ValueError("Caulking uses one root release")
    package = config["packages"]["."]
    expected = {
        "release-type": "simple",
        "version-file": "VERSION",
        "include-component-in-tag": False,
        "include-v-in-tag": True,
        "changelog-path": "CHANGELOG.md",
    }
    for key, value in expected.items():
        if package.get(key) != value:
            raise ValueError(f"Unexpected release configuration: {key}")
    if not (root / package["changelog-path"]).is_file():
        raise ValueError("Release changelog is missing")
    print(f"Release configuration consistent: {version}")


if __name__ == "__main__":
    validate(Path(__file__).resolve().parents[1])
