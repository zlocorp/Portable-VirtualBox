"""Contracts for a disposable-host VBoxSup cleanup proof, not general uninstaller safety."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/vbox_sup_cleanup.ps1"

class VBoxSupCleanupContract(unittest.TestCase):
    def test_only_disposable_host_with_verified_original_package(self):
        text = SCRIPT.read_text(encoding="utf-8")
        for expected in (
            "RUNNER_ENVIRONMENT", "github-hosted", "GITHUB_ACTIONS",
            "GITHUB_REPOSITORY", "RUNNER_TEMP", "services_before",
            "pnputil.stdout.txt", "system_driver_matches_package",
            "startvm_returned_zero", "poweroff_succeeded", "orphaned_vm_process_count",
            "VBoxSDS.exe", "--unregservice", "VBoxSup.sys", "VBoxSup.inf",
            "Get-FileHash", "Get-AuthenticodeSignature",
            "WaitForExit", "cleanup-results.json"):
            self.assertIn(expected, text)

    def test_no_unscoped_cleanup_or_forced_package_removal(self):
        active = "\n".join(line for line in SCRIPT.read_text(encoding="utf-8").splitlines()
                           if not line.lstrip().startswith("#"))
        for pattern in (
            r"(?i)\btaskkill\b", r"(?i)\bStop-Process\b", r"(?i)\bRemove-Service\b",
            r"(?i)\bsc\s+delete\b", r"(?i)\bRemove-Item\b", r"(?i)\bStart-Process\b[^\n]*(?:msiexec|VirtualBoxVM|VBoxManage)",
            r"(?i)(?:/delete-driver|/uninstall)\s+[^\n]*/force",
            r"(?i)\bstartvm\b",
        ):
            self.assertNotRegex(active, pattern)
        self.assertRegex(active, r"(?i)/delete-driver")
        self.assertRegex(active, r"(?i)/uninstall")

    def test_stale_service_cleanup_requires_removed_driver_and_exact_service(self):
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("Run-Bounded $sc 'delete VBoxSup'", text)
        self.assertIn("service_delete", text)
        self.assertIn("system_driver_file_present", text)
        self.assertIn("published_inf_present", text)
        self.assertIn("final_vbox_services", text)

    def test_published_inf_name_requires_restrictive_pattern(self):
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("Published Name:", text)
        self.assertRegex(text, r"oem\[0-9\].*\\\.inf")
        self.assertIn("existing", text.lower())

if __name__ == "__main__":
    unittest.main()
