"""Source ordering supplement; executable Windows fixtures prove behavior."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CleanupAdmissionContract(unittest.TestCase):
    def test_prospective_proof_is_committed_after_read_only_preflight(self):
        text = (ROOT / 'scripts/vbox_sup_cleanup.ps1').read_text()
        self.assertIn('[string]$ProspectiveProofJson', text)
        boundary = text.index('# Commit cleanup admission only after the read-only preflight.')
        self.assertLess(text.index("'VBoxSDS changed during idle wait'"), boundary)
        self.assertGreater(text.index('[IO.FileMode]::CreateNew'), boundary)
        self.assertGreater(text.index('Invoke-ProtectedSds -Operation UnregisterFull'), boundary)
        self.assertIn('.Flush($true)', text)

    def test_full_worker_does_not_persist_proof_before_cleanup(self):
        text = (ROOT / 'scripts/privileged_session_worker.ps1').read_text()
        full = text[text.index("$receipt=Get-Content -LiteralPath (Join-Path $session 'session.json')"):]
        self.assertNotIn('Set-Content -LiteralPath $proof', full)
        self.assertEqual(full.count('-ProspectiveProofJson $prospectiveProof'), 2)

    def test_disposable_helper_exercises_real_locked_inf_refusal_and_retry(self):
        text = (ROOT / 'tests/windows/check_helper_boundary.ps1').read_text()
        self.assertIn("Helper-Action Finish $cycle 70 'preflight-locked-inf'", text)
        self.assertIn('[IO.FileShare]::None', text)
        self.assertIn('preflight_refusal_then_cleanup_verified', text)
        self.assertIn('assertNoCleanupEffects', text)


if __name__ == '__main__':
    unittest.main()
