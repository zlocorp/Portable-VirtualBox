"""Tests exercise actual byte parsing, not a fake extraction subprocess."""
import hashlib
from pathlib import Path
import sys
import struct
from tempfile import TemporaryDirectory
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from pe_fixture import make_pe, payload_resources
from oracle_extract import inspect_packages, extract_packages


class OracleExtractTests(unittest.TestCase):
    def test_pe32_and_pe32plus_payloads(self):
        for plus in (False, True):
            data = make_pe(payload_resources(), plus=plus)
            packages = inspect_packages(data)
            self.assertEqual(len(packages), 1)
            self.assertEqual(packages[0].architecture, 'amd64')
            self.assertEqual(packages[0].name, 'VirtualBox-7.2.20-175154-Win.msi')
            self.assertEqual(bytes(packages[0].payload)[:8], bytes.fromhex('d0cf11e0a1b11ae1'))

    def test_oracle_english_us_resources_are_supported(self):
        for plus in (False, True):
            with self.subTest(plus=plus):
                packages = inspect_packages(make_pe(payload_resources(), plus=plus, language=0x0409))
                self.assertEqual(len(packages), 1)
                self.assertEqual(packages[0].architecture, 'amd64')

    def test_mixed_or_unsupported_resource_languages_fail_closed(self):
        resources = payload_resources()
        for languages in ({'MANIFEST': 0x0409, 'HDR_00': 0, 'BIN_00': 0x0409},
                          {'MANIFEST': 0, 'HDR_00': 0, 'BIN_00': 0x0409}, 0x0407):
            with self.subTest(languages=languages), self.assertRaises(ValueError):
                inspect_packages(make_pe(resources, language=languages))

    def test_bad_manifest_headers_and_payloads_fail_closed(self):
        good = payload_resources()
        variants = [dict(good, MANIFEST=b'x' * 16), dict(good, MANIFEST=good['MANIFEST'][:-1] + b'\0'),
                    dict(good, HDR_00=b'x'), dict(good, BIN_00=b'not MSI'),
                    {k: v for k, v in good.items() if k != 'BIN_00'}, payload_resources(arch=99)]
        for res in variants:
            with self.subTest(res=list(res)), self.assertRaises(ValueError):
                inspect_packages(make_pe(res))

    def test_traversal_reserved_names_and_duplicate_names_rejected(self):
        for filename in ('../escape.msi', 'C:\\evil.msi', 'NUL.msi', 'file:stream.msi'):
            with self.subTest(filename=filename), self.assertRaises(ValueError):
                inspect_packages(make_pe(payload_resources(filename)))
        res = payload_resources()
        res['MANIFEST'] = res['MANIFEST'][:-1] + bytes([2])
        res['HDR_01'] = res['HDR_00'].replace(b'BIN_00', b'BIN_01')
        res['BIN_01'] = res['BIN_00']
        with self.assertRaises(ValueError):
            inspect_packages(make_pe(res))

    def test_malformed_pe_and_resource_bounds_rejected(self):
        good = make_pe(payload_resources())
        mutations = [b'', b'MZ', good[:100], good[:-10]]
        for offset, value in ((0x3c, 0xffffffff), (0x98 + 96 + 16, 0xffffffff),
                              (0x200 + 20, 0x80000000), (0x200 + 40, 0xffffffff)):
            changed = bytearray(good)
            struct.pack_into('<I', changed, offset, value)
            mutations.append(bytes(changed))
        for bad in mutations:
            with self.subTest(size=len(bad)), self.assertRaises(ValueError):
                inspect_packages(bad)

    def test_extracts_to_new_directory_with_exact_payload_hash(self):
        data = make_pe(payload_resources())
        with TemporaryDirectory() as folder:
            exe = Path(folder) / 'fixture.exe'
            exe.write_bytes(data)
            out = Path(folder) / 'staged'
            report = extract_packages(exe, out, hashlib.sha256(data).hexdigest())
            self.assertEqual(report[0]['sha256'], hashlib.sha256(payload_resources()['BIN_00']).hexdigest())
            self.assertEqual((out / report[0]['name']).read_bytes(), payload_resources()['BIN_00'])
            self.assertTrue((out / 'packages.json').is_file())
            self.assertFalse((out / '.incomplete').exists())
            with self.assertRaises(FileExistsError):
                extract_packages(exe, out, hashlib.sha256(data).hexdigest())

    def test_bad_hash_leaves_destination_absent(self):
        with TemporaryDirectory() as folder:
            exe = Path(folder) / 'fixture.exe'
            exe.write_bytes(make_pe(payload_resources()))
            out = Path(folder) / 'staged'
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                extract_packages(exe, out, '0' * 64)
            self.assertFalse(out.exists())


if __name__ == '__main__':
    unittest.main()
