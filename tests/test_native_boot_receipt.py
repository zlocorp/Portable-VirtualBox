"""Native VM boot receipt must be confirmed from genuine compiled AutoIt output
AND fresh VBoxManage/Windows observations, not inferred from a green workflow.
"""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
class NativeReceiptContract(unittest.TestCase):
    def test_compiled_entrypoint_is_explicitly_nonshipping(self):
        entry=(ROOT/"source/Portable-VirtualBox.au3").read_text(encoding="utf-8-sig")
        self.assertIn('#include "PortableCIVM.au3"',entry)
        self.assertIn('Case "--ci-vm-session"',entry)
        self.assertIn('_PCVM_Execute(@ScriptDir)',entry)
        self.assertNotIn('--ci-vm-session  --',entry.split('Case "--help"')[1].split('Case "--version"')[0])
    def test_poweroff_requires_bounded_read_only_uuid_confirmation(self):
        source=(ROOT/"source/PortableCIVM.au3").read_text(encoding="utf-8-sig")
        self.assertIn('While TimerDiff($offTimer) < 30000',source)
        self.assertIn('If Not $offConfirmed Then ExitLoop',source)
        self.assertIn('_PCVM_UUID($r["output"]) <> $uuid',source)
        self.assertIn('Sleep(300)',source)
        self.assertLess(source.index('If Not $offConfirmed Then ExitLoop'),source.index('$stopped = True'))
    def test_receipt_requires_independent_probe(self):
        script=(ROOT/"scripts/check_native_vm_boot.ps1").read_text(encoding="utf-8")
        for fragment in (
            "GITHUB_ACTIONS", "RUNNER_ENVIRONMENT", "RUNNER_TEMP",
            "Native VM: VERIFIED_OWN_BOOT_AND_POWEROFF",
            "Get-AuthenticodeSignature", "VBOX_USER_HOME",
            "showvminfo", 'VMState="poweroff"', "UUID",
            "VBoxSup", "VBoxSDS", "VirtualBoxVM", "WaitForExit",
            "vm-boot-results.json", "startvm_returned_zero",
            "poweroff_succeeded", "orphaned_vm_process_count",
        ): self.assertIn(fragment,script)
        self.assertNotRegex(script, r"(?im)^\s*\$home\s*=")
        for fragment in ("sc delete", "taskkill", "Stop-Service", "msiexec"):
            self.assertNotIn(fragment,script)
if __name__=="__main__":
    unittest.main()
