"""Failure-only bounded read-only registration diagnostics, not retry authority."""
from pathlib import Path
import os
import shutil
import subprocess
import unittest
ROOT = Path(__file__).resolve().parents[1]
SHELL = os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh') or shutil.which('powershell.exe')
class SdsFailureCapture(unittest.TestCase):
    @unittest.skipUnless(SHELL, 'PowerShell required')
    def test_actual_failure_renderer_and_collector(self):
        r=subprocess.run([SHELL,'-NoProfile','-File',str(ROOT/'tests/windows/check_sds_failure_capture.ps1')],cwd=ROOT,capture_output=True,text=True,timeout=45)
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertIn('SDS_FAILURE_CAPTURE_PASS',r.stdout)
