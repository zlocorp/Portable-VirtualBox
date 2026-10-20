"""Safety contract for read-only VBoxSup installation reference."""
from pathlib import Path
import re
import unittest
S=Path(__file__).resolve().parents[1]/"scripts/vbox_sup_probe.ps1"
class VBoxSupContracts(unittest.TestCase):
    def test_works_on_exact_disposable_reference_only(self):
        s=S.read_text(encoding="utf-8")
        for key in ("GITHUB_ACTIONS","GITHUB_REPOSITORY","RUNNER_ENVIRONMENT","VBoxSup","InstallReport","Get-AuthenticodeSignature","Get-FileHash","sup-results.json"):
            self.assertIn(key,s)
    def test_cannot_mutate_driver(self):
        s="\n".join(line for line in S.read_text(encoding="utf-8").splitlines() if not line.lstrip().startswith("#"))
        for pattern in [r"(?i)\b(?:sc|net)\s+(?:start|stop|delete|create)\b",
                        r"(?i)\b(?:pnputil|dism|rundll32|regsvr32|msiexec|Start-Service|Stop-Service|Remove-Service|New-Service|Copy-Item|Remove-Item|taskkill|startvm)\b"]:
            self.assertNotRegex(s,pattern)
if __name__=="__main__":unittest.main()
