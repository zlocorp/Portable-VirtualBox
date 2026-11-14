"""Regression cases: real temporary files and controlled network responses."""
import hashlib
import io
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import oracle_release as oracle
from vm_inventory import inventory


class Response(io.BytesIO):
    def __init__(self, data, url):
        super().__init__(data)
        self.url = url


class DownloadRegressions(unittest.TestCase):
    data = b'test payload, not executable'
    url = 'https://download.virtualbox.org/virtualbox/7.2.20/VirtualBox-7.2.20-175154-Win.exe'
    sha = hashlib.sha256(data).hexdigest()

    def test_destination_created_during_download_is_never_overwritten(self):
        with TemporaryDirectory() as folder:
            dest = Path(folder) / 'target.exe'
            def opener(*args, **kwargs):
                dest.write_bytes(b'other operation')
                return Response(self.data, self.url)
            with self.assertRaises(FileExistsError):
                oracle.download_verified(self.url, dest, self.sha, opener=opener)
            self.assertEqual(dest.read_bytes(), b'other operation')

    def test_foreign_partial_created_by_concurrent_operation_survives(self):
        with TemporaryDirectory() as folder:
            dest = Path(folder) / 'target.exe'
            foreign = dest.with_name(dest.name + '.partial')
            def opener(*args, **kwargs):
                foreign.write_bytes(b'owned by somebody else')
                raise OSError('network failure')
            with self.assertRaises(OSError):
                oracle.download_verified(self.url, dest, self.sha, opener=opener)
            self.assertEqual(foreign.read_bytes(), b'owned by somebody else')
            self.assertFalse(dest.exists())

    def test_https_redirect_to_other_host_rejected(self):
        with TemporaryDirectory() as folder:
            with self.assertRaises(ValueError):
                oracle.download_verified(self.url, Path(folder) / 'vbox.exe', self.sha,
                    opener=lambda *a, **k: Response(self.data, 'https://example.org/evil.exe'))

    def test_prefix_is_not_url_validation(self):
        for suffix in ('../evil.exe', '7.2.20/../../evil.exe', '7.2.20/test.exe?x=1', '7.2.20/%2e%2e/evil.exe'):
            with self.subTest(suffix=suffix), TemporaryDirectory() as folder:
                with self.assertRaises(ValueError):
                    oracle.download_verified('https://download.virtualbox.org/virtualbox/' + suffix,
                        Path(folder) / 'vbox.exe', self.sha, opener=lambda *a, **k: io.BytesIO(self.data))

    def test_manifest_rejects_windows_special_names(self):
        for name in ('CON', 'AUX.txt', 'file:stream', 'bad?.exe', 'bad".exe'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                oracle.parse_sha256_manifest(self.sha + '  ' + name)

    def test_installer_revision_must_be_numeric(self):
        with self.assertRaises(ValueError):
            oracle.find_windows_installer({'VirtualBox-7.2.20-evil-Win.exe': self.sha}, '7.2.20')

    def test_response_limit_and_temp_cleanup(self):
        with TemporaryDirectory() as folder:
            dest = Path(folder) / 'vbox.exe'
            with self.assertRaises(ValueError):
                oracle.download_verified(self.url, dest, self.sha,
                    opener=lambda *a, **k: io.BytesIO(self.data), max_bytes=3)
            self.assertEqual(list(Path(folder).iterdir()), [])


class XMLRegressions(unittest.TestCase):
    def test_utf16_doctype_rejected_without_modification(self):
        with TemporaryDirectory() as folder:
            xml = Path(folder) / 'VirtualBox.xml'
            data = ('<?xml version="1.0" encoding="UTF-16"?>'
                    '<!DOCTYPE VirtualBox [<!ENTITY x "payload">]>'
                    '<VirtualBox><Global><MachineRegistry/></Global></VirtualBox>').encode('utf-16')
            xml.write_bytes(data)
            with self.assertRaises(ValueError):
                inventory(xml)
            self.assertEqual(xml.read_bytes(), data)

    def test_utf16_without_doctype_supported(self):
        with TemporaryDirectory() as folder:
            xml = Path(folder) / 'VirtualBox.xml'
            xml.write_bytes('<?xml version="1.0" encoding="UTF-16"?><VirtualBox/>'.encode('utf-16'))
            self.assertEqual(inventory(xml), [])

    def test_windows_ambiguous_paths_are_not_local(self):
        for src in ('Machines/CON.vbox', 'Machines/foo:stream', 'Machines/trailing. ', 'Machines/AUX'):
            with self.subTest(src=src), TemporaryDirectory() as folder:
                xml = Path(folder) / 'VirtualBox.xml'
                xml.write_text('<VirtualBox><Global><MachineRegistry><MachineEntry uuid="id" src="' + src +
                    '"/></MachineRegistry></Global></VirtualBox>', encoding='utf-8')
                self.assertFalse(inventory(xml)[0].inside_profile)

    def test_foreign_xml_namespace_is_rejected(self):
        with TemporaryDirectory() as folder:
            xml = Path(folder) / 'VirtualBox.xml'
            xml.write_text('<VirtualBox xmlns="urn:not-virtualbox"/>', encoding='utf-8')
            with self.assertRaises(ValueError):
                inventory(xml)

    def test_non_registry_machine_entries_are_not_interpreted(self):
        with TemporaryDirectory() as folder:
            xml = Path(folder) / 'VirtualBox.xml'
            xml.write_text('<VirtualBox><ExtraData><MachineEntry uuid="id" src="foo.vbox"/></ExtraData></VirtualBox>')
            self.assertEqual(inventory(xml), [])


if __name__ == '__main__':
    unittest.main()
