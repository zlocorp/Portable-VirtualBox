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
        self.assertIn("ae40bb2b2770fcd264cb9d03de2d278a621997b33956e88a2de5edc900873d2a",s)
        self.assertIn("65a3ac87ff3be03e4db4837139eb286e4e1387e1fd5d758d72c6ff745f6e10db",s)
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
