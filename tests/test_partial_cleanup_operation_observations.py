"""Execute partial cleanup diagnostics with controlled system boundaries."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHELL = os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh') or shutil.which('powershell.exe')

class PartialCleanupOperationObservations(unittest.TestCase):
    @unittest.skipUnless(SHELL, 'PowerShell required')
    def test_actual_partial_effect_body_retains_dispatch_outcomes(self):
        result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-File',
                                 str(ROOT / 'tests/windows/check_partial_cleanup_operation_observations.ps1')],
                                cwd=ROOT, capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PARTIAL_CLEANUP_OPERATION_OBSERVATIONS_PASS', result.stdout)
