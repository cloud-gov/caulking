"""Regression tests for parsing, diagnostics, encoding, and safe loading."""

import ast
import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from cloud_gov_pre_commit_checks import check_json, check_yaml
from cloud_gov_pre_commit_checks.__main__ import main


class SyntaxChecksTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, filename, content):
        path = self.root / filename
        path.write_text(content, encoding="utf-8")
        return str(path)

    def run_check(self, check, *filenames):
        errors = io.StringIO()
        with contextlib.redirect_stderr(errors):
            status = check(list(filenames))
        return status, errors.getvalue()

    def test_valid_unicode_and_space_filenames(self):
        for check, suffix, text in (
            (check_json, "json", '{"café": "雪"}'),
            (check_yaml, "yaml", "café: 雪\n"),
        ):
            with self.subTest(suffix=suffix):
                paths = [self.write(f"{name}.{suffix}", text) for name in ("a b", "雪")]
                self.assertEqual(self.run_check(check, *paths), (0, ""))
                for path in paths:
                    self.assertEqual(Path(path).read_text(encoding="utf-8"), text)

    def test_all_invalid_files_reported_with_filenames(self):
        for check, suffix, text in (
            (check_json, "json", '{"key": }'),
            (check_yaml, "yaml", "key: [unterminated"),
        ):
            with self.subTest(suffix=suffix):
                first = self.write(f"bad file.{suffix}", text)
                second = self.write(f"bad 雪.{suffix}", text)
                status, errors = self.run_check(check, first, second)
                self.assertEqual(status, 1)
                self.assertIn(first, errors)
                self.assertIn(second, errors)
                self.assertNotIn("Traceback", errors)
                self.assertIn("line", errors)

    def test_missing_and_non_utf8_files(self):
        invalid = self.root / "invalid encoding"
        invalid.write_bytes(b"\xff")
        missing = str(self.root / "missing file")
        for check in (check_json, check_yaml):
            with self.subTest(check=check.__name__):
                status, errors = self.run_check(check, str(invalid), missing)
                self.assertEqual(status, 1)
                self.assertIn(str(invalid), errors)
                self.assertIn(missing, errors)

    def test_json_bom_rejected_like_legacy(self):
        path = self.write("bom.json", '\ufeff{"key": "value"}')
        with (
            open(path, encoding="utf-8") as stream,
            self.assertRaises(json.JSONDecodeError),
        ):
            json.load(stream)
        self.assertEqual(self.run_check(check_json, path)[0], 1)

    def test_json_stdlib_semantics(self):
        path = self.write("stdlib.json", '{"key": 1, "key": NaN}')
        self.assertEqual(self.run_check(check_json, path), (0, ""))

    def test_parser_value_errors_report_filename_and_continue(self):
        cases = [(check_yaml, "yaml", "date: 2026-02-30\n", "key: [")]
        if hasattr(sys, "get_int_max_str_digits") and sys.get_int_max_str_digits():
            cases.append((check_json, "json", "9" * 5000, '{"key": }'))
        for check, suffix, value_error, syntax_error in cases:
            with self.subTest(suffix=suffix):
                first = self.write(f"invalid value.{suffix}", value_error)
                second = self.write(f"later invalid.{suffix}", syntax_error)
                status, errors = self.run_check(check, first, second)
                self.assertEqual(status, 1)
                self.assertIn(first, errors)
                self.assertIn(second, errors)
                self.assertNotIn("Traceback", errors)

    def test_module_dispatch_and_usage(self):
        for mode, content in (("json", '{"key": 1}'), ("yaml", "key: 1")):
            path = self.write(f"dispatch.{mode}", content)
            self.assertEqual(self.run_check(main, mode, path), (0, ""))
        for args in ((), ("unknown",)):
            status, errors = self.run_check(main, *args)
            self.assertEqual(status, 2)
            self.assertIn("usage:", errors)

    def test_package_python39_syntax(self):
        package = Path(__file__).resolve().parents[1] / "cloud_gov_pre_commit_checks"
        for path in package.glob("*.py"):
            with self.subTest(path=path.name):
                ast.parse(path.read_text(encoding="utf-8"), feature_version=(3, 9))

    def test_json_runs_without_site_packages_or_yaml(self):
        path = self.write("no yaml.json", '{"key": "雪"}')
        source = str(Path(__file__).resolve().parents[1])
        result = subprocess.run(
            [
                sys.executable,
                "-I",
                "-S",
                "-c",
                (
                    "import importlib.util, sys; "
                    "assert importlib.util.find_spec('yaml') is None; "
                    "sys.path.insert(0, sys.argv[1]); "
                    "from cloud_gov_pre_commit_checks.__main__ import main; "
                    "status = main(['json', *sys.argv[2:]]); "
                    "assert 'yaml' not in sys.modules; sys.exit(status)"
                ),
                source,
                path,
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_yaml_single_document_and_bom(self):
        multiple = self.write("multiple.yaml", "---\nkey: 1\n---\nkey: 2\n")
        self.assertEqual(self.run_check(check_yaml, multiple)[0], 1)
        bom = self.write("bom.yaml", "\ufeffkey: value\n")
        empty = self.write("empty.yaml", "")
        self.assertEqual(self.run_check(check_yaml, bom, empty), (0, ""))

    def test_yaml_python_object_is_rejected_without_execution(self):
        marker = self.root / "executed"
        payload = "!!python/object/apply:builtins.eval\n- " + json.dumps(
            f"__import__('pathlib').Path({str(marker)!r}).touch()"
        )
        path = self.write("unsafe object.yaml", payload)
        status, errors = self.run_check(check_yaml, path)
        self.assertEqual(status, 1)
        self.assertIn(path, errors)
        self.assertIn("constructor", errors)
        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
