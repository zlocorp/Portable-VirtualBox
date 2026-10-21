"""A truthful, dependency-minimal diagnostic ZIP (never an Oracle/driver release)."""
import os
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"scripts"))
from package_preview import build_preview, MEMBERS

class DiagnosticPreviewTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        (self.root/"build").mkdir()
        self.exe=self.root/"build"/"Portable-VirtualBox_x64.exe"
        self.exe.write_bytes(b"MZ"+b"x"*12000)
        (self.root/"README.md").write_text("readme",encoding="utf-8")
        (self.root/"LICENSE.md").write_text("original license",encoding="utf-8")
        for name in ("README.ru.md", "CHANGELOG.md", "FEATURES.md", "CREDITS.md", "THIRD_PARTY_NOTICES.md"):
            (self.root/name).write_text("attribution fixture: "+name, encoding="utf-8")
        # Deliberately leave unwanted old/external binaries in repo.
        (self.root/"source"/"i_data"/"tools").mkdir(parents=True)
        (self.root/"source"/"i_data"/"tools"/"devcon_x64.exe").write_bytes(b"x")
        self.output=self.root/"build"/"Portable-VirtualBox-diagnostic-preview.zip"

    def test_minimal_preview_does_not_bundle_old_tools_or_oracle(self):
        receipt=build_preview(self.root,self.exe,self.output)
        self.assertTrue(self.output.is_file())
        self.assertEqual(receipt["members"],sorted(MEMBERS))
        with zipfile.ZipFile(self.output) as z:
            self.assertEqual(sorted(z.namelist()),sorted(MEMBERS))
            self.assertEqual(z.read("Portable-VirtualBox.exe"),self.exe.read_bytes())
            self.assertEqual(z.read("LICENSE.md"),b"original license")
            notice=z.read("PREVIEW-NOT-A-HYPERVISOR.txt").decode("utf-8")
            self.assertIn("does not launch virtual machines",notice)
            self.assertIn("development diagnostic preview",notice)
        self.assertEqual(len(receipt["sha256"]),64)
        self.assertTrue(self.output.with_suffix(".zip.sha256").is_file())

    def test_archive_carries_attribution_and_feature_status(self):
        build_preview(self.root,self.exe,self.output)
        with zipfile.ZipFile(self.output) as archive:
            for name in ("CREDITS.md", "THIRD_PARTY_NOTICES.md", "README.ru.md", "CHANGELOG.md", "FEATURES.md"):
                self.assertIn(name, archive.namelist())
                self.assertEqual(archive.read(name),(self.root/name).read_bytes())

    def test_no_zip_is_created_when_credits_missing(self):
        (self.root/"CREDITS.md").unlink()
        with self.assertRaises(ValueError):
            build_preview(self.root,self.exe,self.output)
        self.assertFalse(self.output.exists())

    def test_rejects_overwrite_without_mutating_existing_result(self):
        self.output.write_bytes(b"foreign")
        with self.assertRaises(FileExistsError):build_preview(self.root,self.exe,self.output)
        self.assertEqual(self.output.read_bytes(),b"foreign")

    def test_rejects_invalid_executable_and_symlinks(self):
        self.exe.write_bytes(b"not an executable")
        with self.assertRaises(ValueError):build_preview(self.root,self.exe,self.output)
        self.exe.unlink()
        if hasattr(os,"symlink"):
            try:os.symlink(self.root/"README.md",self.exe)
            except (OSError,NotImplementedError):self.skipTest("symlink privileges unavailable")
            with self.assertRaises(ValueError):build_preview(self.root,self.exe,self.output)

    def test_requires_license_and_readme_before_publication(self):
        (self.root/"LICENSE.md").unlink()
        with self.assertRaises(ValueError):build_preview(self.root,self.exe,self.output)
        self.assertFalse(self.output.exists())

if __name__=="__main__":unittest.main()
