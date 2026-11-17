"""File-only MSI layout tests. No installer, registry mutation or VM execution."""
import copy
import importlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))


def metadata():
    return {
        'Directory': [
            {'Directory': 'TARGETDIR', 'Directory_Parent': '', 'DefaultDir': 'SourceDir'},
            {'Directory': 'INSTALLDIR', 'Directory_Parent': 'TARGETDIR', 'DefaultDir': 'VirtualBox'},
            {'Directory': 'alias', 'Directory_Parent': 'INSTALLDIR', 'DefaultDir': '.'},
            {'Directory': 'drivers', 'Directory_Parent': 'alias', 'DefaultDir': 'drivers'},
            {'Directory': 'SUP', 'Directory_Parent': 'drivers', 'DefaultDir': 'vboxsup:source'},
            {'Directory': 'system', 'Directory_Parent': 'TARGETDIR', 'DefaultDir': 'System32'},
        ],
        'Component': [
            {'Component': 'main', 'Directory_': 'alias'},
            {'Component': 'driver', 'Directory_': 'SUP'},
            {'Component': 'external', 'Directory_': 'system'},
        ],
        'File': [
            {'File': 'main_key', 'Component_': 'main', 'FileName': 'VBOX~1.EXE|VirtualBox.exe', 'FileSize': '3', 'Attributes': '512', 'Sequence': '1', 'Version': '7.2.20.25154'},
            {'File': 'driver_key', 'Component_': 'driver', 'FileName': 'VBoxSup.sys', 'FileSize': '4', 'Attributes': '16384', 'Sequence': '2'},
            {'File': 'common_key', 'Component_': 'main', 'FileName': 'COMMON~1.TXT|Русский файл.txt', 'FileSize': '6', 'Attributes': '512', 'Sequence': '3'},
        ],
        'Media': [
            {'DiskId': '1', 'LastSequence': '2', 'Cabinet': '#product.cab'},
            {'DiskId': '2', 'LastSequence': '3', 'Cabinet': 'common.cab'},
        ],
    }


class MsiStagingTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(importlib.util.find_spec('msi_staging'), 'MSI layout/staging implementation is missing')
        self.api = importlib.import_module('msi_staging')

    def plan(self, data=None, **kwargs):
        return self.api.build_plan(data or metadata(), compressed=True, **kwargs)

    def test_names_aliases_and_media_boundary(self):
        plan = self.plan()
        self.assertEqual([x.relative for x in plan.files], ['VirtualBox.exe', 'drivers/vboxsup/VBoxSup.sys', 'Русский файл.txt'])
        self.assertEqual([x.cabinet for x in plan.files], ['#product.cab', '#product.cab', 'common.cab'])
        self.assertEqual(plan.total_bytes, 13)
        self.assertEqual(plan.excluded, ())

    def test_file_outside_app_root_is_excluded(self):
        data = metadata(); data['File'][2]['Component_'] = 'external'
        plan = self.plan(data)
        self.assertEqual(len(plan.files), 2)
        self.assertEqual(plan.excluded, ('common_key',))

    def test_missing_or_ambiguous_tables_and_joins_fail(self):
        for table in ('Directory', 'Component', 'File', 'Media'):
            data = metadata(); del data[table]
            with self.subTest(table=table), self.assertRaises(ValueError): self.plan(data)
        for table, key in [('Directory', 'Directory'), ('Component', 'Component'), ('File', 'File')]:
            data = metadata(); row = copy.deepcopy(data[table][0]); row[key] = row[key].upper(); data[table].append(row)
            with self.subTest(duplicate=table), self.assertRaises(ValueError): self.plan(data)
        data = metadata(); data['File'][0]['Component_'] = 'absent'
        with self.assertRaises(ValueError): self.plan(data)
        data = metadata(); data['Component'][0]['Directory_'] = 'absent'
        with self.assertRaises(ValueError): self.plan(data)

    def test_directory_cycles_and_dangling_parents_fail(self):
        for parent in ('drivers', 'absent'):
            data = metadata(); data['Directory'][2]['Directory_Parent'] = parent
            with self.subTest(parent=parent), self.assertRaises(ValueError): self.plan(data)

    def test_windows_paths_and_filename_collisions_fail(self):
        for name in ('../escape', 'a\\b', 'C:escape', 'NUL.txt', 'file.', 'a|b|c', 'bad:stream', 'COM¹.txt'):
            data = metadata(); data['File'][0]['FileName'] = name
            with self.subTest(name=name), self.assertRaises(ValueError): self.plan(data)
        for name in ('..', 'C:foo:bar', 'a/b'):
            data = metadata(); data['Directory'][4]['DefaultDir'] = name
            with self.subTest(directory=name), self.assertRaises(ValueError): self.plan(data)
        data = metadata(); data['File'][2]['FileName'] = 'virtualbox.EXE'
        with self.assertRaises(ValueError): self.plan(data)
        data = metadata(); data['File'][0]['FileName'] = 'drivers'
        with self.assertRaises(ValueError): self.plan(data)

    def test_invalid_sizes_sequences_or_compression_fail(self):
        for field, value in [('FileSize','-1'), ('FileSize',str(2**40)), ('Sequence','0'), ('Sequence','3'), ('Attributes','8192')]:
            data = metadata(); data['File'][0][field] = value
            with self.subTest(field=field,value=value), self.assertRaises(ValueError): self.plan(data)
        with self.assertRaises(ValueError): self.api.build_plan(metadata(), compressed=False)
        with self.assertRaises(ValueError): self.plan(max_total_bytes=12)

    def test_invalid_media_and_unknown_cabinets_fail(self):
        for column, value in [('Cabinet','../cab'), ('Cabinet','#../cab'), ('Cabinet',''), ('LastSequence','1'), ('DiskId','1')]:
            data = metadata(); data['Media'][1][column] = value
            with self.subTest(column=column,value=value), self.assertRaises(ValueError): self.plan(data)
        data = metadata(); data['Media'][1]['Cabinet'] = '#PRODUCT.CAB'
        with self.assertRaises(ValueError): self.plan(data)

    def test_cabinet_members_must_match_sizes_and_unique_keys(self):
        plan = self.plan(); want = [x for x in plan.files if x.cabinet=='#product.cab']
        self.api.validate_members([('main_key',3), ('driver_key',4)], want)
        for entries in ([('main_key',3)], [('main_key',4),('driver_key',4)], [('main_key',3),('MAIN_KEY',3),('driver_key',4)], [('../escape',0)]):
            with self.subTest(entries=entries), self.assertRaises(ValueError): self.api.validate_members(entries,want)

    def payloads(self, folder):
        root = Path(folder); root.mkdir()
        data = {'main_key': b'abc', 'driver_key': b'1234', 'common_key': b'common'}
        for name, value in data.items(): (root/name).write_bytes(value)
        return {name: root/name for name in data}

    def test_assembly_creates_exact_tree_and_hash_inventory(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); payloads = self.payloads(root/'raw'); output = root/'Тест app64'
            report = self.api.assemble(self.plan(),payloads,output)
            self.assertEqual(report['file_count'],3); self.assertEqual(report['total_bytes'],13)
            self.assertEqual((output/'Русский файл.txt').read_bytes(),b'common')
            self.assertEqual(len(list(output.rglob('*.sys'))),1)
            self.assertEqual(json.loads((output/'.prepared.json').read_text())['file_count'],3)
            self.assertTrue(all(len(row['sha256'])==64 for row in report['files']))
            self.assertEqual(payloads['main_key'].read_bytes(),b'abc')

    def test_existing_destination_and_concurrent_destination_survive(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); payloads=self.payloads(root/'raw'); output=root/'app64'; output.mkdir(); marker=output/'keep'; marker.write_bytes(b'user')
            with self.assertRaises(FileExistsError): self.api.assemble(self.plan(),payloads,output)
            self.assertEqual(marker.read_bytes(),b'user')
            output2=root/'race'; original=self.api.publish_directory
            def racing(source, target):
                target.mkdir(); (target/'foreign').write_bytes(b'user'); original(source,target)
            with patch.object(self.api,'publish_directory',side_effect=racing), self.assertRaises(FileExistsError): self.api.assemble(self.plan(),payloads,output2)
            self.assertEqual((output2/'foreign').read_bytes(),b'user')

    def test_incomplete_payload_never_publishes_app64(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); payloads=self.payloads(root/'raw'); output=root/'app64'
            payloads['main_key'].write_bytes(b'wrong size')
            with self.assertRaises(ValueError): self.api.assemble(self.plan(),payloads,output)
            self.assertFalse(output.exists()); self.assertEqual(payloads['main_key'].read_bytes(),b'wrong size')

    def test_symlink_payload_rejected_and_target_untouched(self):
        if os.name=='nt': self.skipTest('symlink privilege varies on Windows')
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); payloads=self.payloads(root/'raw'); output=root/'app64'; target=root/'foreign'; target.write_bytes(b'abc')
            payloads['main_key'].unlink(); payloads['main_key'].symlink_to(target)
            with self.assertRaises(ValueError): self.api.assemble(self.plan(),payloads,output)
            self.assertFalse(output.exists()); self.assertEqual(target.read_bytes(),b'abc')

    def test_failed_copy_never_publishes_or_mutates_source(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); payloads=self.payloads(root/'raw'); output=root/'app64'
            with patch.object(self.api,'copy_payload',side_effect=OSError('simulated disk full')), self.assertRaises(OSError): self.api.assemble(self.plan(),payloads,output)
            self.assertFalse(output.exists()); self.assertEqual(payloads['main_key'].read_bytes(),b'abc')


if __name__=='__main__': unittest.main()
