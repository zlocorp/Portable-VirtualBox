"""Isolate input vs output path encoding with a known-good cabinet fixture."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from windows_payload import cabinet_members, extract_cabinet

@unittest.skipUnless(os.name=='nt','Windows cabinet path regression')
class CabinetUnicodeTests(unittest.TestCase):
    def test_unicode_source_and_destination_independently(self):
        with tempfile.TemporaryDirectory(prefix='pvbox-cab-path-') as folder:
            root=Path(folder)
            payload=root/'fixture_key'; payload.write_bytes(b'cabinet-fixture'*257)
            cab=root/'fixture.cab'
            makecab=Path(os.environ['SystemRoot'])/'System32/makecab.exe'
            subprocess.run([str(makecab),str(payload),str(cab)],check=True,capture_output=True,timeout=30)
            expected=[('fixture_key',payload.stat().st_size)]
            self.assertEqual(cabinet_members(cab),expected)
            unicode=root/'Кириллица 测试'; unicode.mkdir()
            unicode_cab=unicode/'fixture.cab'; shutil.copyfile(cab,unicode_cab)
            before=hashlib.sha256(unicode_cab.read_bytes()).hexdigest()
            for source in (cab,unicode_cab):
                with self.subTest(operation='list',unicode_source=source==unicode_cab):
                    self.assertEqual(cabinet_members(source),expected)
            for index,(source,parent) in enumerate(((cab,unicode),(unicode_cab,root),(unicode_cab,unicode))):
                destination=parent/f'out-{index}'; destination.mkdir()
                with self.subTest(operation='extract',unicode_source=source==unicode_cab,unicode_output=parent==unicode):
                    extract_cabinet(source,destination,dict(expected))
                    self.assertEqual((destination/'fixture_key').read_bytes(),payload.read_bytes())
            self.assertEqual(hashlib.sha256(unicode_cab.read_bytes()).hexdigest(),before)

if __name__=='__main__': unittest.main()
