"""Exercise installed isolated module entries without staging the source checkout.

Run from the repo root: python3 tests/try_repo_python_checks.py
Requires pre-commit on PATH and package-index access (or cached packages).
"""

import os
import shlex
import shutil
import subprocess
import tempfile
import unittest
from itertools import product
from pathlib import Path


class TryRepoTest(unittest.TestCase):
    def test_installed_hooks_in_consumer(self):
        source = Path(__file__).resolve().parents[1]
        executable = shutil.which("pre-commit")
        self.assertIsNotNone(executable, "pre-commit must be on PATH")
        # Isolate the framework launcher too: it imports yaml before running hooks.
        # -I ignores PYTHONPATH for this process but leaves it in os.environ for
        # the actual hook subprocess. Use the launcher's own installed interpreter.
        with open(executable, encoding="utf-8") as script:
            interpreter = shlex.split(script.readline().removeprefix("#!").strip())
        command = [*interpreter, "-I", executable]
        with tempfile.TemporaryDirectory(prefix="python-hook-consumer-") as directory:
            root = Path(directory)
            provider = root / "provider"
            # Clone + overlay only hook files: try-repo omits source untracked files.
            # Only this disposable copy is staged; the source index stays untouched.
            subprocess.run(
                [
                    "git",
                    "-c",
                    f"safe.directory={source}",
                    "clone",
                    "--quiet",
                    "--no-hardlinks",
                    str(source),
                    str(provider),
                ],
                check=True,
            )
            files = (
                ".pre-commit-hooks.yaml",
                "pyproject.toml",
                "cloud_gov_pre_commit_checks/__init__.py",
                "cloud_gov_pre_commit_checks/__main__.py",
            )
            for filename in files:
                target = provider / filename
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source / filename, target)
            subprocess.run(["git", "add", "--", *files], cwd=provider, check=True)
            consumer = root / "consumer"
            consumer.mkdir()
            subprocess.run(["git", "init", "--quiet", str(consumer)], check=True)
            # A repository-local yaml.py must not shadow the installed dependency.
            (consumer / "yaml.py").write_text(
                "from pathlib import Path\n"
                "Path('yaml-imported').touch()\n"
                "raise RuntimeError('consumer yaml.py imported')\n",
                encoding="utf-8",
            )
            env = dict(os.environ, PRE_COMMIT_HOME=str(consumer / "cache"))
            env.pop("PYTHONPATH", None)
            for suffix, good, bad in (
                ("json", '{"café": "雪"}', '{"key": }'),
                ("yaml", "café: 雪\n", "key: [unterminated"),
            ):
                for (valid, text), pythonpath in product(
                    ((True, good), (False, bad)), (None, ".")
                ):
                    with self.subTest(
                        suffix=suffix, valid=valid, pythonpath=pythonpath
                    ):
                        if pythonpath is None:
                            env.pop("PYTHONPATH", None)
                        else:
                            env["PYTHONPATH"] = pythonpath
                        path = (
                            consumer / f"{'good' if valid else 'bad'} 雪 file.{suffix}"
                        )
                        path.write_text(text, encoding="utf-8")
                        result = subprocess.run(
                            [
                                *command,
                                "try-repo",
                                str(provider),
                                f"check-{suffix}-selfcontained",
                                "--files",
                                path.name,
                            ],
                            check=False,
                            cwd=consumer,
                            env=env,
                            capture_output=True,
                            text=True,
                        )
                        output = result.stdout + result.stderr
                        print(output)
                        self.assertEqual(result.returncode, 0 if valid else 1, output)
                        self.assertIn("Passed" if valid else "Failed", output)
                        self.assertNotIn("(no files to check)", output)
                        if not valid:
                            self.assertIn(path.name, output)
                            self.assertIn("check failed:", output)
                        self.assertEqual(path.read_text(encoding="utf-8"), text)
                        self.assertFalse((consumer / "yaml-imported").exists())


if __name__ == "__main__":
    unittest.main()
