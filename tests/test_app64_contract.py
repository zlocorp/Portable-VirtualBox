"""Required-runtime inventory is validation of bytes, not executable invocation."""
import importlib
import importlib.util
from pathlib import Path
import struct
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))

class App64ContractTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(importlib.util.find_spec('prepare_app64'),'Application preparation API is missing')
        self.api=importlib.import_module('prepare_app64')

    def pe(self,machine=0x8664):
        b=bytearray(256); b[:2]=b'MZ'; struct.pack_into('<I',b,60,64); b[64:68]=b'PE\0\0'; struct.pack_into('<H',b,68,machine); struct.pack_into('<H',b,88,0x20b)
        return bytes(b)

    def test_required_runtime_files_and_x64_header(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            for name in self.api.REQUIRED_PE:
                path=root/name; path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(self.pe())
            for name in self.api.REQUIRED_DATA:
                path=root/name; path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(b'fixture')
            report=self.api.validate_runtime(root)
            self.assertEqual(report['required_pe_count'],len(self.api.REQUIRED_PE))
            (root/'VirtualBox.exe').write_bytes(self.pe(0x14c))
            with self.assertRaises(ValueError): self.api.validate_runtime(root)

    def test_missing_core_and_malformed_pe_are_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            with self.assertRaises((ValueError,OSError)): self.api.validate_runtime(root)
            path=root/'bad.exe'
            for data in (b'',b'MZ',b'MZ'+b'\0'*254):
                path.write_bytes(data)
                with self.assertRaises(ValueError): self.api.pe_machine(path)

    def test_existing_destination_is_refused_before_reading_input(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); output=root/'app64'; output.mkdir(); (output/'keep').write_bytes(b'user')
            with self.assertRaises(FileExistsError): self.api.prepare(root/'absent.exe',output,'0'*64,'7.2.20')
            self.assertEqual((output/'keep').read_bytes(),b'user')

if __name__=='__main__': unittest.main()
