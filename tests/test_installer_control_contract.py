"""Safety boundaries of the ephemeral official-install reference.

These checks do not prove safe installer behavior. Actual execution is only on
a fresh GitHub-hosted disposable runner and is observed separately.
"""
from pathlib import Path
import unittest

SCRIPT=(Path(__file__).resolve().parents[1]/"scripts/official_install_control.ps1")

class OfficialControlContract(unittest.TestCase):
    def test_requires_exact_host_and_signed_package_identity(self):
        s=SCRIPT.read_text(encoding="utf-8")
        self.assertIn("$env:GITHUB_ACTIONS -ne 'true'",s)
        self.assertIn("$env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox'",s)
        self.assertIn("67875d993fe2460f4515fc4571feeffe0b3542f2ac450920332f8a1d53d566e8",s)
        self.assertIn("6eb8849bfad98f3dacd37d89a0520facca51183ed14c6634f3eda91a4a6b5868",s)
    def test_bounded_minimal_feature_and_no_global_cleanup(self):
        s=SCRIPT.read_text(encoding="utf-8")
        self.assertIn("ADDLOCAL=VBoxApplication",s)
        self.assertIn("/qn /norestart REBOOT=ReallySuppress",s)
        self.assertIn("WaitForExit",s)
        self.assertIn("Kill()",s)
        self.assertNotIn("taskkill",s.lower())
        self.assertNotIn("Stop-Service",s)
        self.assertNotIn("Remove-Service",s)
        self.assertNotIn("VBoxManage startvm",s)
if __name__=="__main__":unittest.main()
