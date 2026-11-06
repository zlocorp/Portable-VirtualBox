"""Multi-VM relocation discovery is public and strictly read-only.

Full behavior is tested with AutoIt on hosted Windows and the compiled CLI.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BatchPlanContract(unittest.TestCase):
    def source(self, path):
        return (ROOT / path).read_text(encoding='utf-8-sig')

    def test_new_batch_planner_is_a_readonly_observer(self):
        p = self.source('source/PortableVmBatchPlan.au3')
        for key in ('Func _PVB_Plan(', 'Func _PVB_Text(', '_PVI_RegistryEntries(',
                    '_PVI_Inspect(', '_PVR_StaleSource(', '_PVR_LocalMachine(',
                    '_PVR_AncillaryLocal(', '_PVI_DirectMachine(', '_PVI_MediaLocation(',
                    '_PBK_Offline(', '_PBK_Hash(', 'REVIEW_ONLY', 'MAX_CANDIDATES'):
            self.assertIn(key, p)
        for unsafe in ('VBoxManage.exe', 'unregistervm', 'registervm', 'Run(', 'RunWait(',
                       'FileWrite(', 'FileDelete(', 'FileMove(', 'RegWrite(',
                       'ProcessClose(', '#RequireAdmin', '_MS_Start(', '_PB_Worker('):
            lines = '\n'.join(x for x in p.splitlines() if not x.lstrip().startswith(';'))
            self.assertNotIn(unsafe, lines)

    def test_batch_backup_requires_same_plan_and_verified_copy_without_registration(self):
        plan = self.source('source/PortableVmBatchPlan.au3')
        main = self.source('source/Portable-VirtualBox.au3')
        native = self.source('tests/native/test_vm_batch_plan.au3')
        compiled = self.source('scripts/check_vm_rebind_plan.ps1')
        for marker in ('Func _PVB_Backup($root, $dest)',
                       'If $before["status"] <> "REVIEW_ONLY" Then Return $before',
                       '_PBK_ValidPath($root, $dest)', '_PBK_Create($root, $dest)',
                       '_PBK_Verify($dest)', '_PVB_Plan($root)',
                       '$after["report"] <> $before["report"]',
                       '$after["registry_sha256"] <> $before["registry_sha256"]',
                       '"BACKUP_ONLY"'):
            self.assertIn(marker, plan)
        self.assertIn('Case "--prepare-multi-vm-rebind"', main)
        self.assertIn('Local $preparedMulti = _PVB_Backup(@ScriptDir, $CmdLine[$iFirst + 1])', main)
        self.assertIn('If $preparedMulti["status"] == "BACKUP_ONLY" Then Exit 0', main)
        self.assertIn('batch backup verifies every VM and original registry', native)
        self.assertIn('batch backup refuses existing destination', native)
        self.assertIn('batch unsafe source never creates new backup', native)
        self.assertIn('batch-verified-backup', compiled)
        self.assertIn('batch-backup-repeat-refused', compiled)
        self.assertIn('batch-backup-source-blocked', compiled)

    def test_gui_inventory_includes_readonly_multi_vm_report(self):
        gui = self.source('source/LauncherGui.au3')
        native = self.source('tests/native/test_vm_batch_plan.au3')
        self.assertIn('#include "PortableVmBatchPlan.au3"', gui)
        self.assertIn('Func _LG_InventoryText($root)', gui)
        self.assertIn('Local $batch = _PVB_Plan($root)', gui)
        self.assertIn('If $batch["status"] == "REVIEW_ONLY" Then $show &= @CRLF & _PVB_Text($batch)', gui)
        self.assertEqual(gui.count('_LG_InventoryText(@ScriptDir)'), 2)
        self.assertIn('Russian GUI inventory includes moved batch report', native)
        self.assertIn('English GUI inventory explicitly read-only', native)

    def test_entrypoint_uses_independent_readonly_command(self):
        main = self.source('source/Portable-VirtualBox.au3')
        self.assertIn('PortableVmBatchPlan.au3', main)
        self.assertIn('Case "--plan-multi-vm-rebind"', main)
        self.assertIn('Local $multiPlan = _PVB_Plan(@ScriptDir)', main)
        self.assertIn('_PVB_Text($multiPlan)', main)
        self.assertIn('--plan-multi-vm-rebind', main)
        # Registration mutation still requires exactly one verified VM and a
        # separate explicitly confirmed Manager action.
        single = self.source('source/PortableVmRebind.au3')
        self.assertIn('$entries.length <> 1', single)

    def test_native_and_compiled_acceptance_have_mixed_negative_cases(self):
        native = self.source('tests/native/test_vm_batch_plan.au3')
        compiled = self.source('scripts/check_vm_rebind_plan.ps1')
        for key in ('batch plan finds two relocated VMs',
                    'different prior roots block batch plan',
                    'one malformed machine blocks entire batch',
                    'missing media blocks entire batch',
                    'live old source blocks entire batch',
                    'saved guest state blocks entire batch',
                    'batch report does not authorize any Oracle operation'):
            self.assertIn(key, native)
        for key in ('batch-plan-two-vms', 'batch-plan-mixed-origins',
                    'batch-plan-invalid-uuid', 'batch-plan-missing-media',
                    'batch-plan-single-refusal'):
            self.assertIn(key, compiled)
        workflow = self.source('.github/workflows/ci.yml')
        self.assertIn('check_vm_rebind_plan.ps1', workflow)
        tests = self.source('scripts/test-native.ps1')
        self.assertIn('test_*.au3', tests)


if __name__ == '__main__':
    unittest.main()
