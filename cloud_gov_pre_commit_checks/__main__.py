"""Dispatch installed syntax checks under Python's isolated mode."""

import sys

from . import check_json, check_yaml


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    checks = {"yaml": check_yaml, "json": check_json}
    if not args or args[0] not in checks:
        print(
            "usage: python -I -m cloud_gov_pre_commit_checks {yaml,json} [files ...]",
            file=sys.stderr,
        )
        return 2
    return checks[args[0]](args[1:])


if __name__ == "__main__":
    sys.exit(main())
