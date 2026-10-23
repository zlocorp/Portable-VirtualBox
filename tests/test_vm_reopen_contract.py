"""Contract for a second run reusing an existing disposable VirtualBox profile."""
from pathlib import Path
import unittest

SCRIPT=Path(__file__).resolve().parents[1]/"scripts/vbox_vm_reopen_probe.ps1"

class ReopenProbeContracts(unittest.TestCase):
    def test_same_vm_configuration_survives_a_full_driver_teardown(self):
        s=SCRIPT.read_text(encoding="utf-8")
        for k in (
            "RUNNER_ENVIRONMENT","GITHUB_ACTIONS","VBOX_USER_HOME",
            "first_boot","first_uuid","reopened_uuid","list","vms",
            "showvminfo","startvm","controlvm","poweroff",
            "WaitForExit","same_vm_identity","reopen-results.json",
            "vm-boot-results.json","VBoxSup"
        ):
            self.assertIn(k,s)
    def test_no_new_vm_creation_or_unscoped_process_termination(self):
        code="\n".join(line for line in SCRIPT.read_text(encoding="utf-8").splitlines()
                       if not line.lstrip().startswith("#"))
        for bad in ("createvm","unregistervm","--delete","taskkill","Stop-Process","Remove-Service","msiexec"):
            self.assertNotIn(bad,code)

if __name__=="__main__":
    unittest.main()
