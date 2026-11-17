"""Partial recovery must delay its one-shot proof until read-only checks pass."""
from pathlib import Path
import unittest
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]

class PartialCleanupAdmission(unittest.TestCase):
    def test_worker_passes_prospective_proof_without_persisting(self):
        worker = (ROOT / 'scripts/privileged_session_worker.ps1').read_text()
        partial = worker[worker.index("if ($Action -eq 'Recover' -and $IncompletePreparation)"):worker.index("$receipt=Get-Content -LiteralPath (Join-Path $session 'session.json')")]
        self.assertIn('-ProspectiveProofJson $prospectiveProof', partial)
        self.assertNotIn('Set-Content -LiteralPath $partialProof', partial)

    def test_commit_follows_partial_cleanup_preflight(self):
        source = (ROOT / 'scripts/vbox_sup_partial_cleanup.ps1').read_text()
        self.assertIn('[string]$ProspectiveProofJson', source)
        start = source.index('# Commit partial cleanup admission')
        self.assertLess(source.index('Assert-FailedStartStopped\nRequire-Quiescent'), start)
        self.assertGreater(source.index('[IO.FileMode]::CreateNew'), start)
        self.assertGreater(source.index('Invoke-ProtectedSds -Operation UnregisterPartial'), start)
        self.assertIn('.Flush($true)', source)

    @unittest.skipUnless(os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh'), 'PowerShell required')
    def test_actual_script_refusal_and_one_shot_admission(self):
        shell = os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh')
        run = subprocess.run([shell, '-NoProfile', '-NonInteractive', '-File', str(ROOT / 'tests/windows/check_partial_cleanup_admission.ps1')], capture_output=True, text=True, timeout=120)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn('PARTIAL_CLEANUP_ADMISSION_PASS', run.stdout)
