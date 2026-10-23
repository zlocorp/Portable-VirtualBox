"""Use the same temporary-volume/path layout as real Oracle preparation."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from windows_payload import cabinet_members, extract_cabinet

@unittest.skipUnless(os.name=='nt','Windows cabinet regression')
class CabinetWorkspaceTests(unittest.TestCase):
    def test_workspace_unicode_directory_and_hidden_staging(self):
        base=os.environ.get('RUNNER_TEMP',tempfile.gettempdir())
        with tempfile.TemporaryDirectory(prefix='pvbox-source-') as source, tempfile.TemporaryDirectory(prefix='pvbox-workspace-',dir=base) as work:
            src=Path(source); data=b'known-cabinet-bytes'*4096
            (src/'file_key').write_bytes(data)
            cab=src/'product.cab'
            subprocess.run([str(Path(os.environ['SystemRoot'])/'System32/makecab.exe'),'/D','CompressionType=LZX','/D','CompressionMemory=21',str(src/'file_key'),str(cab)],check=True,capture_output=True,timeout=30)
            stage=Path(work)/'portable Тест'/'.vbox-prepare-fixture'; stage.mkdir(parents=True)
            staged_cab=stage/'embedded-0.cab'; shutil.copyfile(cab,staged_cab)
            self.assertEqual(cabinet_members(staged_cab),[('file_key',len(data))])
            raw=stage/'raw-0'; raw.mkdir()
            extract_cabinet(staged_cab,raw,{'file_key':len(data)})
            self.assertEqual((raw/'file_key').read_bytes(),data)

    def test_invalid_cabinet_does_not_write_a_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); cabinet=root/'broken.cab'; cabinet.write_bytes(b'MSCF'+b'\0'*64)
            target=root/'out'; target.mkdir()
            with self.assertRaises((OSError,ValueError)):
                extract_cabinet(cabinet,target,{'safe_key':1})
            self.assertEqual(list(target.iterdir()),[])

if __name__=='__main__': unittest.main()
