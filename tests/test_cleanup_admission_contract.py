"""Source ordering supplement; executable Windows fixtures prove behavior."""
from pathlib import Path
import unittest
import re

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


    def test_locked_inf_guard_is_reachable_and_success_requires_its_proof(self):
        text = (ROOT / 'tests/windows/check_helper_boundary.ps1').read_text()
        cycles = {int(value) for value in re.search(r'foreach \(\$cycle in @\(([^)]*)\)\)', text).group(1).split(',')}
        for marker in ("# A real sharing-denied read", 'Assert-PriorJournals $session $refusalJournals'):
            guard = re.findall(r'if \(\$cycle -eq (\d+)\)', text[:text.index(marker)])[-1]
            self.assertIn(int(guard), cycles)
        success = text.index("$proof.durable_journal_verified=$true")
        self.assertLess(text.index("if (-not $proof.preflight_refusal_then_cleanup_verified) { throw 'Locked-INF preflight retry was not verified' }"), success)

    def test_real_recover_preflight_retry_is_mandatory_and_retains_evidence(self):
        text = (ROOT / 'tests/windows/check_orphan_recovery.ps1').read_text()
        refused = text.index("70 'preflight-locked-inf'")
        succeeded = text.index("0 'recover-orphan'")
        self.assertLess(refused, succeeded)
        self.assertIn('[IO.FileShare]::None', text)
        self.assertIn('preflight-refusal-evidence.json', text)
        self.assertIn('Preflight refusal did not identify the locked owned INF', text)
        self.assertLess(text.index('Assert-PriorJournals $session $refusalJournals', succeeded), text.index('$proof.orphan_recovery_verified=$true'))
        self.assertIn("if (-not $proof.preflight_refusal_then_recovery_verified) { throw 'Recovery preflight retry was not verified' }", text)


if __name__ == '__main__':
    unittest.main()
