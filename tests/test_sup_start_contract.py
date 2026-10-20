"""Safety contract: start only exclusively staged signed VBoxSup on disposable CI."""
from pathlib import Path
import re
import unittest
SOURCE=Path(__file__).resolve().parents[1]/"scripts/vbox_sup_start_owned.ps1"
class DriverStartContract(unittest.TestCase):
    def test_scope_and_ownership_checks(self):
        s=SOURCE.read_text(encoding="utf-8")
        for mark in ("GITHUB_ACTIONS","RUNNER_ENVIRONMENT","RUNNER_TEMP",
                     "pnputil_exit_code","standalone-VBoxSup-primitive-INF-pnputil",
                     "services_before","services_after","Get-FileHash",
                     "a4d29ed6ba1c9ad74110cb86d10c0d8c9f492a1b3f6836963139380b02b3ed90",
                     "WaitForExit","start","VBoxSup","sup-start-results.json"):
            self.assertIn(mark,s)
    def test_never_stops_deletes_or_starts_other_components(self):
        s="\n".join(x for x in SOURCE.read_text(encoding="utf-8").splitlines() if not x.lstrip().startswith("#"))
        for expr in (r"(?i)\b(?:taskkill|Stop-Service|Remove-Service|New-Service|Start-Service|msiexec)\b",
                     r"(?i)\bsc\s+(?:stop|delete|create)\b",
                     r"(?i)\bstartvm\b"):
            self.assertNotRegex(s,expr)
if __name__=="__main__":unittest.main()
