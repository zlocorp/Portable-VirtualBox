"""Guards for a bounded, disposable-host-only VM boot capability probe."""
from pathlib import Path
import re
import unittest
SCRIPT=Path(__file__).resolve().parents[1]/"scripts/vbox_vm_boot_probe.ps1"
class VMBootContracts(unittest.TestCase):
    def test_only_verified_host_and_private_empty_vm(self):
        s=SCRIPT.read_text(encoding="utf-8")
        for key in ("GITHUB_ACTIONS","RUNNER_ENVIRONMENT","InstallReport","VBoxSup",
                    "VBOX_USER_HOME","machinefolder","createvm","startvm","headless",
                    "controlvm","poweroff","WaitForExit","vm-boot-results.json"):
            self.assertIn(key,s)
    def test_no_unscoped_mutation_or_guest_media(self):
        s="\n".join(x for x in SCRIPT.read_text(encoding="utf-8").splitlines() if not x.lstrip().startswith("#"))
        for expr in [r"(?i)\btaskkill\b",r"(?i)\b(?:Stop-Service|Remove-Service|New-Service|sc\s+delete)\b",
                     r"(?i)\bmsiexec\b",r"(?i)\bVBoxManage\s+unregistervm\b",
                     r"(?i)\b(?:VBoxManage\s+storageattach|VBoxManage\s+createmedium)\b"]:
            self.assertNotRegex(s,expr)
if __name__=="__main__":unittest.main()
