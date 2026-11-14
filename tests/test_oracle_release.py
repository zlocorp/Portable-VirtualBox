"""Offline tests for release selection, integrity checks and non-overwrite policy."""
import hashlib
import io
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from oracle_release import (  # noqa: E402
    download_verified, find_windows_installer, parse_sha256_manifest, release_root
)


class OracleReleaseTests(unittest.TestCase):
    def setUp(self):
        self.payload = b"test-fixture: not a VirtualBox executable"
        self.sha = hashlib.sha256(self.payload).hexdigest()
        self.name = "VirtualBox-7.2.20-175154-Win.exe"

    def test_fixed_version_and_official_host(self):
        self.assertEqual(release_root("7.2.20"),
                         "https://download.virtualbox.org/virtualbox/7.2.20/")
        for bad in ("latest", "7.2.20/../", "http://example.com/", "7.2.20?download=1"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                release_root(bad)

    def test_parses_and_selects_exact_windows_installer(self):
        checksum = self.sha
        manifest = "{}  {}\n{} *VBoxGuestAdditions_7.2.20.iso\n".format(
            checksum.upper(), self.name, checksum)
        filename, sha = find_windows_installer(parse_sha256_manifest(manifest), "7.2.20")
        self.assertEqual(filename, self.name)
        self.assertEqual(sha, checksum)
        with self.assertRaises(ValueError):
            parse_sha256_manifest("{}  {}\n{}  {}\n".format(
                checksum, self.name, checksum, self.name))

    def test_bad_manifest_is_rejected(self):
        for data in ("", "not a checksum", self.sha + "  ../escape.exe",
                     self.sha + "  folder\\file.exe"):
            with self.subTest(data=data), self.assertRaises(ValueError):
                parse_sha256_manifest(data)

    def test_verification_is_atomic_and_does_not_overwrite(self):
        with TemporaryDirectory() as folder:
            path = Path(folder) / self.name
            got = download_verified(
                release_root("7.2.20") + self.name, path, self.sha,
                opener=lambda *_args, **_kwargs: io.BytesIO(self.payload),
            )
            self.assertEqual(got, self.sha)
            self.assertEqual(path.read_bytes(), self.payload)
            self.assertFalse(path.with_name(path.name + ".partial").exists())
            with self.assertRaises(FileExistsError):
                download_verified(release_root("7.2.20") + self.name, path, self.sha)

    def test_download_reports_real_bytes_and_rejects_wrong_content_length(self):
        class Response(io.BytesIO):
            def __init__(self, payload, length):
                super().__init__(payload)
                self.headers = {"Content-Length": length}

        with TemporaryDirectory() as folder:
            dest = Path(folder) / self.name
            readings = []
            download_verified(release_root("7.2.20") + self.name, dest, self.sha,
                opener=lambda *_a, **_kw: Response(self.payload, str(len(self.payload))),
                progress=lambda done, total: readings.append((done, total)))
            self.assertEqual(readings, [(0, len(self.payload)), (len(self.payload), len(self.payload))])
            dest.unlink()
            with self.assertRaisesRegex(ValueError, "Truncated or inconsistent"):
                download_verified(release_root("7.2.20") + self.name, dest, self.sha,
                    opener=lambda *_a, **_kw: Response(self.payload, str(len(self.payload) + 3)))
            self.assertFalse(dest.exists())

    def test_mismatch_removes_partial_and_does_not_install(self):
        with TemporaryDirectory() as folder:
            path = Path(folder) / self.name
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                download_verified(
                    release_root("7.2.20") + self.name, path, "0" * 64,
                    opener=lambda *_args, **_kwargs: io.BytesIO(self.payload),
                )
            self.assertFalse(path.exists())
            self.assertFalse(path.with_name(path.name + ".partial").exists())


if __name__ == "__main__":
    unittest.main()
