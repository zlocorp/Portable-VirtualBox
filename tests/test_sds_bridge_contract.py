"""Closed SDS wrapper checks. Mocked effects are not native lifetime evidence."""
from pathlib import Path
import os
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = os.environ.get("PVBOX_TEST_POWERSHELL") or shutil.which("powershell") or shutil.which("pwsh")

class SdsBridgeContract(unittest.TestCase):
    @unittest.skipUnless(POWERSHELL, "PowerShell unavailable")
    def test_protected_wrapper_never_falls_back(self):
        result = subprocess.run([POWERSHELL, "-NoProfile", "-File",
                                 str(ROOT / "tests/windows/check_sds_bridge_wrapper.ps1"),
                                 "-Repository", str(ROOT)],
                                cwd=ROOT, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("SDS_BRIDGE_WRAPPER_PASS", result.stdout)

    def test_unregistration_transport_does_not_replace_authority_gates(self):
        for filename, operation, result in (
            ("vbox_sup_cleanup.ps1", "UnregisterFull", "$sdsExit"),
            ("vbox_sup_partial_cleanup.ps1", "UnregisterPartial", "$result"),
        ):
            with self.subTest(filename=filename):
                source = (ROOT / "scripts" / filename).read_text()
                call = source.index("Invoke-ProtectedSds -Operation " + operation)
                gate = source.index("if (" + result + " -ne 0 -or", call)
                self.assertLess(call, gate)
                self.assertIn(r"Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS'", source[gate:gate + 180])
                self.assertIn("if (-not $sdsResult.WithinDeadline)", source[call:gate])
                self.assertIn("if (-not $sdsResult.ExitCodeKnown)", source[call:gate])

    def test_partial_recovery_keeps_sds_attempt_existence_refusal(self):
        source = (ROOT / "scripts/vbox_sup_partial_cleanup.ps1").read_text()
        gate = source.index("if (-not $markerExists -and")
        operation = source.index("$result=Run-Bounded") if "$result=Run-Bounded" in source else source.index("UnregisterPartial")
        self.assertLess(gate, operation)
        self.assertIn("sds-register.stdout.txt", source[gate:gate + 500])
        self.assertIn("sds-register.stderr.txt", source[gate:gate + 500])
        self.assertIn("SDS may have registered without a durable marker", source[gate:gate + 500])

if __name__ == "__main__":
    unittest.main()
