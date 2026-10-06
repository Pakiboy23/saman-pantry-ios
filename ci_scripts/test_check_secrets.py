"""Exercise the scanner in disposable Git repositories with synthetic keys."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCANNER = Path(__file__).with_name("check_secrets.sh").resolve()
KEYS = ("sk-" + "ant-api-test", "sk-" + "proj-test", "sk-" + "A" * 32)


class CheckSecretsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")
        (self.root / "ci_scripts").mkdir()
        shutil.copy2(SCANNER, self.root / "ci_scripts/check_secrets.sh")
        self.git("add", ".")

    def git(self, *args):
        return subprocess.run(
            ["git", "-C", str(self.root), *args], check=True, capture_output=True
        )

    def track(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        self.git("add", "-f", "--", name)

    def scan(self, **env):
        return subprocess.run(
            ["bash", str(SCANNER)], cwd=self.root, capture_output=True,
            env={**os.environ, **env},
        )

    def test_empty_and_clean_repositories(self):
        self.assertEqual(self.scan().returncode, 0)
        self.track("source.swift", "let value = 42\n")
        self.assertEqual(self.scan().returncode, 0)

    def test_all_key_patterns(self):
        for key in KEYS:
            with self.subTest(key=key):
                self.track("source.swift", key)
                self.assertEqual(self.scan().returncode, 1)

    def test_ignore_rules_cannot_hide_tracked_keys(self):
        self.track("nested/source.swift", KEYS[0])
        for ignore in (".ignore", ".rgignore", ".gitignore", "nested/.ignore",
                       "nested/.rgignore", "nested/.gitignore", ".git/info/exclude"):
            with self.subTest(ignore=ignore):
                path = self.root / ignore
                path.write_text("*.swift\n")
                self.assertEqual(self.scan().returncode, 1)
                path.unlink()

    def test_unusual_filenames(self):
        for name in (".hidden", "space name.swift", "line\nbreak.swift", "-",
                     "--option.swift", "back\\slash.swift"):
            with self.subTest(name=name):
                self.track(name, KEYS[1])
                self.assertEqual(self.scan().returncode, 1)
                self.git("rm", "-f", "--", name)

    def test_only_intentional_exclusions(self):
        for extension in ("png", "jpg", "jpeg", "ttf", "pages", "xcuserstate"):
            self.track(f"nested/asset.{extension}", KEYS[0])
        (self.root / "untracked.swift").write_text(KEYS[0])
        self.assertEqual(self.scan().returncode, 0)
        self.track("nested/source.swift", "\0" + KEYS[0])
        self.assertEqual(self.scan().returncode, 1)

    def test_ripgrep_configuration_cannot_disable_detection(self):
        config = self.root / "rg-config"
        config.write_text("--glob=!*.swift\n")
        self.track("source.swift", KEYS[0])
        self.assertEqual(self.scan(RIPGREP_CONFIG_PATH=str(config)).returncode, 1)

    def test_scan_errors_fail(self):
        self.track("missing.swift", "clean")
        (self.root / "missing.swift").unlink()
        result = self.scan()
        self.assertEqual(result.returncode, 2)
        self.assertIn(b"scan failed", result.stderr)

    def test_git_enumeration_errors_fail(self):
        (self.root / ".git/index").write_bytes(b"invalid index")
        self.assertNotEqual(self.scan().returncode, 0)


if __name__ == "__main__":
    unittest.main()
