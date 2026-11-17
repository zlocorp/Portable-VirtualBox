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
    def test_arguments_and_semantic_vm_checks_are_not_silently_ignored(self):
        s=SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn("param([string]$Name,[string[]]$Args)",s)
        self.assertIn("list_fixture",s)
        self.assertIn("inspect_fixture",s)
        self.assertEqual(s.count("function Require-Step"),1)
        self.assertEqual(s.count("guest_os_booted=$false"),1)

    def test_no_unscoped_mutation_or_guest_media(self):
        s="\n".join(x for x in SCRIPT.read_text(encoding="utf-8").splitlines() if not x.lstrip().startswith("#"))
        for expr in [r"(?i)\btaskkill\b",r"(?i)\b(?:Stop-Service|Remove-Service|New-Service|sc\s+delete)\b",
                     r"(?i)\bmsiexec\b",r"(?i)\bVBoxManage\s+unregistervm\b",
                     r"(?i)\b(?:VBoxManage\s+storageattach|VBoxManage\s+createmedium)\b"]:
            self.assertNotRegex(s,expr)
if __name__=="__main__":unittest.main()
