"""The public relocation planner cannot mutate Oracle registrations or system state."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]

class RelocationPlanContract(unittest.TestCase):
    def text(self,path):
        return (ROOT/path).read_text(encoding="utf-8-sig")
    def test_only_backup_is_writable(self):
        p=self.text("source/PortableVmRebind.au3")
        for requirement in (
            "Func _PVR_Plan(", "Func _PVR_Backup(", "Func _PVR_StaleSource(",
            "exact-moved-vm-no-changes-applied",
            "registered-uuid-differs-from-machine", "external-missing-or-unsafe-medium",
            "_PVI_LoadXml(", "_PVI_Inspect(", "_PVI_MediaLocation(",
            "_PBK_Offline()", "_PBK_Create(", "_PBK_Verify(", "_PBK_Hash(",
            "old-machine-still-present-or-unreadable", "source-changed-after-verified-backup"):
            self.assertIn(requirement,p)
        for forbidden in ("VBoxManage.exe", "Run(", "RunWait(", "ProcessClose(",
                          "FileDelete(", "FileMove(", "FileWrite(", "RegWrite(",
                          "unregistervm", "registervm", "#RequireAdmin"):
            self.assertNotIn(forbidden,p)
    def test_public_executable_has_readonly_plan_and_verified_backup(self):
        entry=self.text("source/Portable-VirtualBox.au3")
        gui=self.text("source/LauncherGui.au3")
        for term in ('Case "--plan-vm-rebind"', 'Case "--prepare-vm-rebind"',
                     '_PVR_Plan(@ScriptDir)', '_PVR_Backup(@ScriptDir', '_PVR_Text('):
            self.assertIn(term,entry)
        self.assertIn('Case $idVmAudit',gui)
        self.assertIn('_PVR_Plan(@ScriptDir)',gui)
        self.assertIn('PortableVmRebind.au3',entry)
        self.assertIn('PortableVmRebind.au3',gui)
    def test_native_and_compiled_vm_rebind_real_tests_present(self):
        self.assertTrue((ROOT/"tests/native/test_portable_vm_rebind.au3").is_file())
        win=self.text("scripts/check_vm_rebind_plan.ps1")
        self.assertIn('--plan-vm-rebind',win)
        self.assertIn('--prepare-vm-rebind',win)
        self.assertIn('--verify-backup',win)
        self.assertIn('function Invoke-Launcher([string]$CommandLine',win)
        self.assertIn('-ArgumentList $CommandLine',win)
        self.assertNotIn('function Invoke-Launcher([string]$Args',win)
        workflow=self.text(".github/workflows/ci.yml")
        self.assertIn('check_vm_rebind_plan.ps1',workflow)
if __name__=="__main__":
    unittest.main()
