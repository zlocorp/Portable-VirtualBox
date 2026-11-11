"""Behavioral driver activation gates; no host services or drivers are touched."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = os.environ.get("PVBOX_TEST_POWERSHELL") or shutil.which("powershell") or shutil.which("pwsh")

@unittest.skipUnless(POWERSHELL, "PowerShell required for isolated activation gate tests")
class DriverStartGateTests(unittest.TestCase):
    def run_gate(self, target):
        result = subprocess.run(
            [POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
             str(ROOT / "tests/windows/check_driver_start_gate.ps1"), "-Repository", str(ROOT), "-Target", target],
            capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"PASS {target} driver start gate", result.stdout)

    def test_failed_stopped_recovery_requires_exact_known_state(self):
        result = subprocess.run(
            [POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
             str(ROOT / "tests/windows/check_failed_start_recovery.ps1"), "-Repository", str(ROOT)],
            capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS failed-stopped recovery", result.stdout)

    def test_activation_failure_preserves_evidence_and_throws(self):
        self.run_gate("Start")

    def test_privileged_prepare_requires_confirmed_start_before_sds(self):
        self.run_gate("Privileged")

    def test_manager_prepare_requires_confirmed_start_before_oracle(self):
        self.run_gate("Manager")

if __name__ == "__main__":
    unittest.main()
