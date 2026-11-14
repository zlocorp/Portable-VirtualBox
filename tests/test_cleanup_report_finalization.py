"""Run the actual cleanup report finalizer without system effects."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest
ROOT = Path(__file__).resolve().parents[1]
SHELL = os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh') or shutil.which('powershell.exe')

class CleanupReportFinalization(unittest.TestCase):
    @unittest.skipUnless(SHELL, 'PowerShell required')
    def test_production_finalizer(self):
        run = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-File',
            str(ROOT/'tests/windows/check_cleanup_report_finalization.ps1')],
            capture_output=True, text=True, timeout=60)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn('CLEANUP_REPORT_FINALIZATION_PASS', run.stdout)
