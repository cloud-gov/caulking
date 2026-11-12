"""Read-only syntax checks installed into pre-commit's Python environments."""

import json
import sys


def _check_files(filenames, load, parse_errors, format_name):
    status = 0
    for filename in filenames:
        try:
            with open(filename, encoding="utf-8") as stream:
                load(stream)
        except (OSError, ValueError, *parse_errors) as error:
            print(f"{filename}: {format_name} check failed: {error}", file=sys.stderr)
            status = 1
    return status


def check_json(argv=None):
    """Validate JSON without importing or depending on PyYAML."""
    return _check_files(
        sys.argv[1:] if argv is None else argv,
        json.load,
        (json.JSONDecodeError,),
        "JSON",
    )


def check_yaml(argv=None):
    """Validate one safe YAML document per file, matching the legacy hook."""
    import yaml

    return _check_files(
        sys.argv[1:] if argv is None else argv,
        yaml.safe_load,
        (yaml.YAMLError,),
        "YAML",
    )
