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
        self.assertIn('_LI("vm.backup_warning")',gui)
        self.assertIn('_LI("vm.backup_warning")',entry)
        self.assertIn('_PVI_Inspect(@ScriptDir)', gui)
        for name in ('gui.vm_audit','vm.header','vm.external','vm.missing','vm.blocked'):
            self.assertIn('Case "'+name+'"',lang)
        for marker in ('Msxml2.DOMDocument.6.0','ProhibitDTD','resolveExternals = False',
                       '_PortableSafeRelativePath','0x400','external_count','missing_count',
                       'FileGetSize','4194304', 'MachineEntry', 'VirtualBox.xml',
                       '_PVI_ReadRegistry(', '_PVI_RegistryTarget('):
            self.assertIn(marker,parser)
        for unsafe in ('FileDelete(', 'DirRemove(', 'Run(', 'RunWait(', 'RegWrite(',
                       'ProcessClose(', '#RequireAdmin','VBoxManage.exe'):
            self.assertNotIn(unsafe,parser)

    def test_registry_inventory_requires_real_global_structure_and_uuid_uniqueness(self):
        parser=(ROOT/'source/PortableVmInventory.au3').read_text(encoding='utf-8-sig')
        native=(ROOT/'tests/native/test_portable_vm_inventory.au3').read_text(encoding='utf-8-sig')
        self.assertIn('Func _PVI_RegistryEntries(', parser)
        self.assertIn('Local $entries = _PVI_RegistryEntries($xml)', parser)
        for marker in ('[local-name()="MachineRegistry"]',
                       '[local-name()="MachineEntry"]', 'namespaceURI',
                       'http://www.virtualbox.org/', 'allEntries.length',
                       'duplicate registration UUID'):
            self.assertIn(marker,parser)
        for phrase in ('two registered local VMs remain clean',
                       'nested or malformed registry is blocked',
                       'duplicate registration UUID is blocked',
                       'registration UUID must match config UUID',
                       'duplicate VM config UUID is blocked'):
            self.assertIn(phrase, native)
        self.assertIn('config_identities', parser)
        self.assertIn('machine_uuids', parser)

    def test_machine_xml_is_direct_not_nested_or_foreign(self):
        source = (ROOT / 'source/PortableVmInventory.au3').read_text(encoding='utf-8-sig')
        native = (ROOT / 'tests/native/test_portable_vm_inventory.au3').read_text(encoding='utf-8-sig')
        self.assertIn('Func _PVI_DirectMachine($xml)', source)
        self.assertIn('Local $machine = _PVI_DirectMachine($xml)', source)
        self.assertIn('String($machine.namespaceURI) <> $ns', source)
        self.assertIn('allMachines.length <> 1', source)
        self.assertIn('rootChildren.length <> 1', source)
        for phrase in ('nested Machine blocks inventory', 'foreign Machine namespace blocks inventory',
                       'extra top-level Machine sibling blocks inventory',
                       'valid machine fixture restored after malformed inputs'):
            self.assertIn(phrase, native)

    def test_compiled_inventory_handles_multiple_real_files_and_malformed_xml(self):
        script = (ROOT / 'scripts/check_vm_inventory.ps1').read_text(encoding='utf-8-sig')
        for marker in ('compiled two registered local VMs',
                       'compiled mismatched VM UUID is rejected',
                       'compiled nested Machine XML is rejected',
                       'compiled foreign Machine namespace is rejected',
                       'compiled direct Machine XML restored'):
            self.assertIn(marker, script)
        self.assertIn('compiled duplicate registration UUID is rejected', script)
        self.assertIn('compiled swapped unique UUIDs are rejected', script)
        self.assertIn('$swappedFirst=$registryEntry.Replace($uuid,$secondId)', script)

    def test_real_native_and_compiled_smoke_exercises_public_feature(self):
        self.assertTrue((ROOT/'tests/native/test_portable_vm_inventory.au3').is_file())
        fixture=(ROOT/'scripts/check_vm_inventory.ps1').read_text(encoding='utf-8')
        self.assertIn('--audit-vms',fixture)
        self.assertIn('external', fixture.lower())
        self.assertIn('missing', fixture.lower())
        workflow=(ROOT/'.github/workflows/ci.yml').read_text(encoding='utf-8')
        self.assertIn('check_vm_inventory.ps1',workflow)

if __name__ == '__main__': unittest.main()
