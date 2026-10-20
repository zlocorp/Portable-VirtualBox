"""Static contract for hosted diagnostic-only VBoxManage experiments.

Actual Oracle binary behavior is recorded separately on a hosted Windows runner.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/vbox_cli_probe.ps1"

class VBoxCliProbeContract(unittest.TestCase):
    def test_bounded_fixed_commands_with_isolated_profile(self):
        s = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("VBOX_USER_HOME", s)
        self.assertIn("$env:GITHUB_ACTIONS -ne 'true'", s)
        self.assertIn("$env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox'", s)
        self.assertIn("VBoxManage.exe", s)
        self.assertIn("'--version'", s)
        self.assertIn("'vms'", s)
        self.assertIn("'systemproperties'", s)
        self.assertIn("WaitForExit", s)
        self.assertIn("Kill()", s)
        self.assertIn("probe-results.json", s)

    def test_no_host_service_or_installer_mutation_in_smoke_script(self):
        s = SCRIPT.read_text(encoding="utf-8")
        self.assertNotRegex(s, re.compile(r"\b(?:sc|net)\s+(?:delete|stop|create|start)\b",re.I))
        self.assertNotRegex(s, re.compile(r"\b(?:Stop-Service|Remove-Service|New-Service|Set-Service|Start-Service|Stop-Process|taskkill|msiexec)\b", re.I))
        self.assertNotRegex(s, re.compile(r"\b(?:RegWrite|RegDelete|reg\s+delete)\b",re.I))
        self.assertNotIn("VirtualBoxVM.exe",s)
        self.assertNotRegex("\n".join(line for line in s.splitlines() if not line.lstrip().startswith("#")),r"(?i)\bstartvm\b")

if __name__=="__main__":
    unittest.main()
