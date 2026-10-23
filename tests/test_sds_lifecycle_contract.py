"""Contracts for disposable-host-only VBoxSDS lifecycle experiment.

Dynamic behavior is established separately by the hosted Windows workflow.
"""
from pathlib import Path
import re
import unittest

SCRIPT=Path(__file__).resolve().parents[1]/"scripts/vbox_sds_lifecycle.ps1"

class VBoxSdsLifecycleContracts(unittest.TestCase):
    def test_only_on_disposable_github_host(self):
        s=SCRIPT.read_text(encoding="utf-8")
        self.assertIn("RUNNER_ENVIRONMENT",s)
        self.assertIn("GITHUB_ACTIONS",s)
        self.assertIn("GITHUB_REPOSITORY",s)
        self.assertIn("RUNNER_TEMP",s)
        self.assertIn("Existing VirtualBox",s)
        self.assertIn("Get-AuthenticodeSignature",s)

    def test_own_registration_or_no_cleanup(self):
        s=SCRIPT.read_text(encoding="utf-8")
        self.assertIn("services_before",s)
        self.assertIn("image_path",s)
        self.assertIn("LocalSystem",s)
        self.assertIn("--unregservice",s.lower())
        self.assertIn("WaitForExit",s)
        self.assertIn("Kill()",s)
        self.assertIn("cleanup_allowed",s)
        self.assertIn("cleanup_exit_code",s)
        self.assertIn("after_cleanup",s)

    def test_no_global_mutations(self):
        s=SCRIPT.read_text(encoding="utf-8")
        code="\n".join(x for x in s.splitlines() if not x.lstrip().startswith("#"))
        for pattern in [
            r"(?i)\btaskkill\b",
            r"(?i)\bStop-Service\b",
            r"(?i)\bRemove-Service\b",
            r"(?i)\bsc\s+(?:delete|stop|create)\b",
            r"(?i)\bStart-Process\s+[^\n]*(?:msiexec|rundll32)",
            r"(?i)\bstartvm\b",
        ]:
            self.assertNotRegex(code,pattern)
if __name__=="__main__":unittest.main()
