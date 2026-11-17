"""Deferred cleanup admission: source contracts plus real Windows script fixture."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHELL = os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('powershell.exe') or shutil.which('pwsh')


class CleanupPreflightAdmission(unittest.TestCase):
    def test_worker_supplies_prospective_proof_instead_of_persisting_it(self):
        source = (ROOT / 'scripts/privileged_session_worker.ps1').read_text()
        full = source[source.index("$receipt=Get-Content -LiteralPath (Join-Path $session 'session.json')", source.index("if ($Action -eq 'Recover' -and $IncompletePreparation)")):]
        self.assertIn('-ProspectiveProofJson', full)
        self.assertNotIn('Set-Content -LiteralPath $proof', full)

    def test_cleanup_has_closed_prospective_parameter(self):
        source = (ROOT / 'scripts/vbox_sup_cleanup.ps1').read_text()
        self.assertIn('[string]$ProspectiveProofJson', source)
        self.assertIn('[IO.FileMode]::CreateNew', source)
        self.assertIn('.Flush($true)', source)
        self.assertNotIn('Remove-Item -LiteralPath $proofPath', source)

    @unittest.skipUnless(SHELL, 'PowerShell required; Windows CI verifies native path semantics')
    def test_actual_cleanup_script_deferred_admission(self):
        run = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-File',
                              str(ROOT / 'tests/windows/check_cleanup_preflight_admission.ps1')],
                             capture_output=True, text=True, timeout=120)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn('CLEANUP_PREFLIGHT_ADMISSION_PASS', run.stdout)
