"""Native cabinet roundtrip on disposable files; no MSI installation or services."""
import hashlib
import importlib
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))

@unittest.skipUnless(os.name=='nt','Native Windows cabinet API')
class WindowsPayloadTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(importlib.util.find_spec('windows_payload'),'Native payload reader is missing')
        self.api=importlib.import_module('windows_payload')

    def test_cabinet_read_and_extract_without_execution(self):
        with tempfile.TemporaryDirectory(prefix='pvbox-cab-') as folder:
            root=Path(folder); src=root/'payload_id'; src.write_bytes(b'fixture-not-executable'*100)
            cab=root/'test.cab'
            makecab=Path(os.environ['SystemRoot'])/'System32/makecab.exe'
            subprocess.run([str(makecab),'/D','CompressionType=MSZIP',str(src),str(cab)],check=True,capture_output=True,timeout=30)
            before=hashlib.sha256(cab.read_bytes()).hexdigest()
            members=self.api.cabinet_members(cab)
            self.assertEqual(members,[('payload_id',src.stat().st_size)])
            dest=root/'private'; dest.mkdir()
            self.api.extract_cabinet(cab,dest,{'payload_id':src.stat().st_size})
            self.assertEqual((dest/'payload_id').read_bytes(),src.read_bytes())
            self.assertEqual(hashlib.sha256(cab.read_bytes()).hexdigest(),before)
            with self.assertRaises(FileExistsError): self.api.extract_cabinet(cab,dest,{'payload_id':src.stat().st_size})
            self.assertEqual((dest/'payload_id').read_bytes(),src.read_bytes())

    def test_invalid_msi_is_not_created_or_modified(self):
        with tempfile.TemporaryDirectory() as folder:
            file=Path(folder)/'absent.msi'
            with self.assertRaises(OSError):
                with self.api.MsiReader(file): pass
            self.assertFalse(file.exists())
            file.write_bytes(b'invalid-fixture')
            with self.assertRaises(OSError):
                with self.api.MsiReader(file): pass
            self.assertEqual(file.read_bytes(),b'invalid-fixture')

if __name__=='__main__': unittest.main()
