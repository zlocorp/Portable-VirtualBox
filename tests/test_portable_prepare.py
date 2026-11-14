"""Standalone offline preparer: exact Oracle identity and no destructive behavior."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase, main
from unittest.mock import patch
import os
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import portable_prepare as pp


class OfflinePreparationTests(TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.root = self.base / "portable"; self.root.mkdir()
        self.installer = self.base / pp.INSTALLER
        self.installer.write_bytes(b"MZ" + b"fake" * 300000)

    def test_version_readonly_and_no_installer_execution(self):
        self.assertEqual(pp.main(["--version"]), 0)
        self.assertEqual(pp.PINNED_SHA256,
                         "afd0ff1656cbe04ed88ce619594ae021419d97cce89fa9bdc443e9a963f1713f")
        self.assertNotIn("subprocess", Path(pp.__file__).read_text())

    def test_name_is_not_accepted_as_checksum(self):
        with self.assertRaisesRegex(ValueError, "pinned SHA-256"):
            pp.candidate(self.installer, self.root, require_windows=False)
        self.assertFalse((self.root / "app64").exists())

    def test_no_arbitrary_external_installer(self):
        foreign = self.base / "VirtualBox-7.2.22-other-Win.exe"
        foreign.write_bytes(self.installer.read_bytes())
        with self.assertRaisesRegex(ValueError, "pinned official"):
            pp.candidate(foreign, self.root, require_windows=False)

    def test_existing_app64_is_not_replaced_even_if_checksum_matches(self):
        app = self.root / "app64"; app.mkdir()
        (app / "keep.txt").write_text("do not delete")
        with self.assertRaises(FileExistsError):
            pp.candidate(self.installer, self.root, require_windows=False)
        self.assertEqual((app / "keep.txt").read_text(), "do not delete")

    def test_reparse_input_directory_rejected(self):
        alias = self.base / "linked"
        try:
            alias.symlink_to(self.root, target_is_directory=True)
        except (NotImplementedError, OSError):
            self.skipTest("symlinks not available")
        with self.assertRaisesRegex(ValueError, "unsafe"):
            pp.candidate(self.installer, alias, require_windows=False)

    def test_preparation_receives_only_compile_time_pinned_hash(self):
        with patch.object(pp, "candidate"), patch.object(pp, "prepare", return_value={
                "file_count": pp.FILE_COUNT, "total_bytes": pp.TOTAL_BYTES}) as run:
            pp.offline_prepare(self.installer, self.root)
        run.assert_called_once_with(self.installer, self.root / "app64", pp.PINNED_SHA256, pp.RELEASE)

    def test_unexpected_finished_inventory_is_not_success(self):
        with patch.object(pp, "candidate"), patch.object(pp, "prepare", return_value={"file_count": 2}):
            with self.assertRaisesRegex(ValueError, "inventory"):
                pp.offline_prepare(self.installer, self.root)

    def test_drive_root_rejected(self):
        with patch.object(pp, "safe_ancestors", return_value=True), patch.object(pp, "regular_file"):
            with self.assertRaisesRegex(ValueError, "drive root"):
                pp.candidate(self.installer, Path(self.root.anchor), require_windows=False)


if __name__ == "__main__":
    main()
