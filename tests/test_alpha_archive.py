"""Integrity verifier for an isolated non-release alpha package.

The ZIP manifest is not a signature. This only verifies package assembly
against build inputs and rejects malformed or extra entries before acceptance.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import tempfile
import unittest
import warnings
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import verify_alpha_archive as alpha


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class AlphaArchiveVerifier(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.archive = self.root / 'alpha.zip'
        self.frontend = self.root / 'frontend.exe'
        self.helper = self.root / 'helper.exe'
        self.entries = {name: b'fixture-' + name.encode('ascii') for name in alpha.REQUIRED_FILES}
        self.frontend.write_bytes(self.entries['Portable-VirtualBox.exe'])
        self.helper.write_bytes(self.entries['Portable-VirtualBox-Helper-Alpha.exe'])

    def make_archive(self, *, additions=(), remove=(), override=None, manifest=None):
        content = dict(self.entries)
        for name in remove:
            content.pop(name)
        content.update(override or {})
        if manifest is None:
            manifest = ''.join(f'{digest(value)}  {name}\r\n' for name, value in sorted(content.items())).encode('ascii')
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with ZipFile(self.archive, 'w', ZIP_DEFLATED) as z:
                for name, value in content.items():
                    z.writestr(name, value)
                z.writestr('SHA256SUMS.txt', manifest)
                for item in additions:
                    if isinstance(item, tuple):
                        z.writestr(*item)
                    else:
                        z.writestr(item, b'extra')

    def verify(self):
        return alpha.verify(self.archive, self.frontend, self.helper)

    def test_complete_known_package_accepts_only_matching_inputs(self):
        self.make_archive()
        result = self.verify()
        self.assertEqual(result['entries'], len(alpha.REQUIRED_FILES) + 1)
        self.assertEqual(result['frontend_sha256'], digest(self.frontend.read_bytes()))
        self.assertEqual(result['helper_sha256'], digest(self.helper.read_bytes()))

    def test_tampered_file_or_manifest_is_rejected(self):
        self.make_archive(override={'CREDITS.md': b'changed'}, manifest=b'0' * 64 + b'  CREDITS.md\n')
        with self.assertRaises(ValueError):
            self.verify()

    def test_missing_or_extra_or_repeated_member_refused(self):
        self.make_archive(remove={'CREDITS.md'})
        with self.assertRaises(ValueError):
            self.verify()
        self.make_archive(additions=['other.exe'])
        with self.assertRaises(ValueError):
            self.verify()
        self.make_archive(additions=[('README.md', b'duplicate')])
        with self.assertRaises(ValueError):
            self.verify()

    def test_path_traversal_and_case_variants_refused(self):
        self.make_archive(additions=['../README.md'])
        with self.assertRaises(ValueError):
            self.verify()
        self.make_archive(additions=['readme.md'])
        with self.assertRaises(ValueError):
            self.verify()

    def test_symlink_entry_refused_even_if_manifest_matches(self):
        marker = ZipInfo('CREDITS.md')
        marker.create_system = 3
        marker.external_attr = (0o120777 << 16)
        with ZipFile(self.archive, 'w', ZIP_DEFLATED) as z:
            for name, value in self.entries.items():
                if name != 'CREDITS.md':
                    z.writestr(name, value)
            z.writestr(marker, b'elsewhere')
            rows = dict(self.entries)
            rows['CREDITS.md'] = b'elsewhere'
            z.writestr('SHA256SUMS.txt', ''.join(f'{digest(value)}  {name}\n' for name, value in sorted(rows.items())))
        with self.assertRaises(ValueError):
            self.verify()

    def test_mutated_paired_executables_refused_even_if_manifest_rehashed(self):
        self.make_archive(override={'Portable-VirtualBox.exe': b'replaced'})
        with self.assertRaises(ValueError):
            self.verify()
        self.make_archive(override={'Portable-VirtualBox-Helper-Alpha.exe': b'replaced'})
        with self.assertRaises(ValueError):
            self.verify()

    def test_empty_member_and_invalid_ascii_manifest_refused(self):
        self.make_archive(override={'VBoxManage.cmd': b''})
        with self.assertRaises(ValueError):
            self.verify()
        self.make_archive(manifest=b'\xff\xfegarbage')
        with self.assertRaises(ValueError):
            self.verify()

    def test_no_zip_file_or_truncated_zip_refused(self):
        with self.assertRaises((ValueError, OSError)):
            self.verify()
        self.archive.write_bytes(b'PK\x03\x04short')
        with self.assertRaises(ValueError):
            self.verify()


class AlphaArchiveWiring(unittest.TestCase):
    def test_windows_candidate_verifies_archive_before_upload(self):
        root = Path(__file__).resolve().parents[1]
        workflow = (root / '.github/workflows/alpha-candidate.yml').read_text(encoding='utf-8')
        package_at = workflow.index('scripts/package_alpha.ps1 -Output')
        verify_at = workflow.index('python -X utf8 scripts/verify_alpha_archive.py')
        upload_at = workflow.index('name: Upload temporary acceptance artifact')
        self.assertLess(package_at, verify_at)
        self.assertLess(verify_at, upload_at)
        self.assertIn('--frontend build/Portable-VirtualBox_x64.exe', workflow)
        self.assertIn('--helper build/Portable-VirtualBox-Helper-Alpha.exe', workflow)
        self.assertIn('build/alpha-verification.json', workflow)
        self.assertIn('tests/test_alpha_archive.py', workflow)


if __name__ == '__main__':
    unittest.main()
