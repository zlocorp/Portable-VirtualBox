"""Safety contract for real mounted VHD letter reassignment, not SUBST aliases."""
from pathlib import Path
import re
import unittest
ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'scripts'/'vbox_vhd_volume.ps1'
class VhdVolumeContract(unittest.TestCase):
    def test_ephemeral_only_vhd_file_identity_and_volume_validation(self):
        code=SCRIPT.read_text(encoding='utf-8')
        for name in ('GITHUB_ACTIONS','RUNNER_ENVIRONMENT','github-hosted',
                     'GITHUB_REPOSITORY','RUNNER_TEMP','BackingFile',
                     'diskpart.exe','create vdisk file','Get-DiskImage',
                     'Get-Disk','Get-Partition','Set-Partition',
                     'NewDriveLetter','Get-Volume','PVBOX_TEMP'):
            self.assertIn(name,code)
    def test_no_host_disk_cleaning_or_general_delete(self):
        code=SCRIPT.read_text(encoding='utf-8')
        for pattern in (r'(?i)\bClear-Disk\b',r'(?i)\bRemove-Disk\b',
                        r'(?i)\bRemove-Partition\b',r'(?i)\bFormat-Volume\b',
                        r'(?i)\bStop-Process\b',r'(?i)\btaskkill\b',
                        r'(?i)\bselect disk [0-9]+'):
            self.assertNotRegex(code,pattern)
if __name__=='__main__': unittest.main()
