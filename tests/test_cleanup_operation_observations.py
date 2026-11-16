"""Actual cleanup effect-body diagnostics under mocked OS boundaries, no authority."""
from pathlib import Path
import os
import shutil
import subprocess
import unittest
ROOT = Path(__file__).resolve().parents[1]
SHELL = os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh') or shutil.which('powershell.exe')
class CleanupOperationObservations(unittest.TestCase):
    @unittest.skipUnless(SHELL, 'PowerShell required')
    def test_actual_operation_body_retains_dispatch_and_result_facts(self):
        r = subprocess.run([SHELL, '-NoProfile', '-File', str(ROOT/'tests/windows/check_cleanup_operation_observations.ps1')], cwd=ROOT, capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout+r.stderr)
        self.assertIn('CLEANUP_OPERATION_OBSERVATIONS_PASS', r.stdout)
