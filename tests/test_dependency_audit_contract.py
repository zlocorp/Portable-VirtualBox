"""Guard against reintroducing retired upstream binaries or language assets."""
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from check_active_tree import problems  # noqa: E402


class ActiveDependencyContracts(unittest.TestCase):
    def test_our_development_tree_is_clean(self):
        self.assertEqual(problems(ROOT), [])

    def test_unwanted_tools_and_translations_are_detected(self):
        with TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "source/i_data/tools").mkdir(parents=True)
            (root / "source/i_data/language").mkdir()
            (root / "source/Aut2Exe").mkdir()
            (root / "source/i_data/settings").mkdir()
            (root / "source/i_data/tools/7za.exe").write_bytes(b"fixture")
            (root / "source/i_data/language/english.ini").write_text("fake", encoding="utf-8")
            result = problems(root)
            self.assertTrue(any("source/i_data" in finding for finding in result))
            self.assertTrue(any("source/Aut2Exe" in finding for finding in result))
            self.assertTrue(any("7za.exe" in finding for finding in result))

    def test_rejects_any_new_vendor_binary_under_active_source(self):
        with TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "source").mkdir()
            (root / "source/vendor.dll").write_bytes(b"fixture")
            self.assertTrue(any("vendor.dll" in problem for problem in problems(root)))

    def test_root_build_file_uses_only_official_external_compiler(self):
        build = (ROOT / "build.bat").read_text(encoding="utf-8-sig").lower()
        self.assertIn("scripts\\build.ps1", build)
        self.assertNotIn("7za.exe", build)
        self.assertNotIn("source\\aut2exe", build)
        script = (ROOT / "scripts/build.ps1").read_text(encoding="utf-8")
        self.assertIn('Join-Path $AutoItRoot "Aut2Exe\\Aut2exe_x64.exe"', script)
        self.assertNotIn("source\\i_data", script)

    def test_historical_source_and_licensing_retained(self):
        self.assertTrue((ROOT / "source/legacy/Portable-VirtualBox.au3.disabled").is_file())
        self.assertTrue((ROOT / "LICENSE.md").is_file())
        self.assertTrue((ROOT / "source/LauncherI18n.au3").is_file())


if __name__ == "__main__":
    unittest.main()
