"""Read-only public VM inventory is a real compiled AutoIt function, not a TODO."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

class VmInventoryContract(unittest.TestCase):
    def test_cli_gui_bilingual_and_safe_parser(self):
        entry=(ROOT/'source/Portable-VirtualBox.au3').read_text(encoding='utf-8-sig')
        gui=(ROOT/'source/LauncherGui.au3').read_text(encoding='utf-8-sig')
        lang=(ROOT/'source/LauncherI18n.au3').read_text(encoding='utf-8-sig')
        parser=(ROOT/'source/PortableVmInventory.au3').read_text(encoding='utf-8-sig')
        self.assertIn('Case "--audit-vms"', entry)
        self.assertIn('_PVI_Inspect(@ScriptDir)', entry)
        self.assertIn('Case $idVmAudit', gui)
        self.assertIn('_PVI_Inspect(@ScriptDir)', gui)
        for name in ('gui.vm_audit','vm.header','vm.external','vm.missing','vm.blocked'):
            self.assertIn('Case "'+name+'"',lang)
        for marker in ('Msxml2.DOMDocument.6.0','ProhibitDTD','resolveExternals = False',
                       '_PortableSafeRelativePath','0x400','external_count','missing_count',
                       'FileGetSize','4194304'):
            self.assertIn(marker,parser)
        for unsafe in ('FileDelete(', 'DirRemove(', 'Run(', 'RunWait(', 'RegWrite(',
                       'ProcessClose(', '#RequireAdmin','VBoxManage.exe'):
            self.assertNotIn(unsafe,parser)

    def test_real_native_and_compiled_smoke_exercises_public_feature(self):
        self.assertTrue((ROOT/'tests/native/test_portable_vm_inventory.au3').is_file())
        fixture=(ROOT/'scripts/check_vm_inventory.ps1').read_text(encoding='utf-8')
        self.assertIn('--audit-vms',fixture)
        self.assertIn('external', fixture.lower())
        self.assertIn('missing', fixture.lower())
        workflow=(ROOT/'.github/workflows/ci.yml').read_text(encoding='utf-8')
        self.assertIn('check_vm_inventory.ps1',workflow)

if __name__ == '__main__': unittest.main()
