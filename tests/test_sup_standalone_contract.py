"""Guardrails for signed primitive VBoxSup driver-only research on hosted Windows."""
from pathlib import Path
import re
import unittest
S=Path(__file__).resolve().parents[1]/"scripts/vbox_sup_standalone.ps1"
class StandaloneSupContract(unittest.TestCase):
    def test_exact_host_and_inputs(self):
        s=S.read_text(encoding="utf-8")
        for required in ("RUNNER_ENVIRONMENT","GITHUB_ACTIONS","RUNNER_TEMP",
            "VBoxSup.sys","VBoxSup.inf","VBoxSup.cat","Get-AuthenticodeSignature",
            "4d4af7a0bf01e97854d5bee9ee2bde9445aad408355bcfdae643f7eef7d523be",
            "pnputil.exe","/add-driver","sup-standalone.json","WaitForExit"):
            self.assertIn(required,s)
    def test_no_unscoped_driver_or_process_cleanup(self):
        s="\n".join(x for x in S.read_text(encoding="utf-8").splitlines() if not x.lstrip().startswith("#"))
        for pattern in (r"(?i)\b(?:taskkill|msiexec|rundll32|Stop-Service|Remove-Service|New-Service|Start-Service)\b",
                        r"(?i)\b(?:sc\s+delete|sc\s+stop|/delete-driver|/uninstall)\b",
                        r"(?i)\bstartvm\b"):
            self.assertNotRegex(s,pattern)
if __name__=="__main__":unittest.main()
