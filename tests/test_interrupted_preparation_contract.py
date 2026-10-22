"""Fail closed at confirmed privileged preparation checkpoints.

Static assertions supplement, never replace, the actual disposable Windows
staging/driver/recovery integration workflow.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

def source(name):
    return (ROOT / name).read_text(encoding='utf-8-sig')

class InterruptedPreparation(unittest.TestCase):
    def test_protected_intent_precedes_mutating_worker(self):
        s = source('source/privilege/SessionHelper.Main.cs')
        self.assertIn('prepare-intent.json', s)
        self.assertIn('VerifyInterruptedSession', s)
        self.assertIn('"pre-system-effects"', s)
        self.assertLess(s.index('WriteNew(intent'), s.index('process.Start()'))
        self.assertIn('VerifyInterruptedSession(session,root,caller.Sid,oldPid,cycle)', s)
        self.assertIn(' -IncompletePreparation', s)
        self.assertIn('OrphanControllerAbsent', s)
        self.assertIn('PinnedBuild.FrontendSha256', s)

    def test_recovery_requires_exclusive_stage_and_optional_strict_receipts(self):
        s = source('scripts/vbox_sup_partial_cleanup.ps1')
        for value in ('pnputil.stdout.txt', 'Published Name:', 'oem[0-9]',
                      'sup-standalone.json', 'sup-start-results.json',
                      'sds-registered.json', 'VBoxSup.sys', 'VBoxSup.inf',
                      'Get-AuthenticodeSignature', 'VBoxSDS.exe',
                      'OriginalControllerCreated', 'cleanup_verified',
                      'driver_package_removed', 'PartialRecovery',
                      'Get-CimInstance', 'Get-VBoxNames', 'Get-VBoxProcesses'):
            self.assertIn(value, s)
        for forbidden in (' /force"', 'Stop-Process', 'taskkill', 'reg delete',
                          'Remove-Item HKLM:', 'Get-ChildItem | Remove-Item'):
            self.assertNotIn(forbidden, s)
        # Require absence of other services/processes before any cleanup effect.
        self.assertLess(s.index('Get-VBoxProcesses'), s.index('Run-Bounded $sdsExe'))

    def test_full_and_partial_recovery_share_bounded_exact_action(self):
        worker = source('scripts/privileged_session_worker.ps1')
        for marker in ('IncompletePreparation', 'prepare-intent.json',
                       'vbox_sup_partial_cleanup.ps1', 'partial-recovery-quiescent.json',
                       'Test-OriginalControllerAbsent', 'TestBreakAfter',
                       "'Stage'", "'Start'", "'Sds'"):
            self.assertIn(marker, worker)
        self.assertIn('vbox_sup_partial_cleanup.ps1', source('scripts/build_session_helper.ps1'))
        self.assertIn('vbox_sup_partial_cleanup.ps1', source('source/privilege/SessionHelper.cs'))

    def test_user_must_explicitly_recover_and_no_regular_distribution(self):
        session = source('source/ManagerSession.au3')
        self.assertIn('prepare-intent.json', session)
        self.assertIn('_MS_FindRecoverable', session)
        self.assertIn('Func _MS_Recover', session)
        self.assertIn('CONSENT_RECOVER', session)
        import sys
        sys.path.insert(0, str(ROOT / 'scripts'))
        from package_preview import MEMBERS
        self.assertEqual(len(MEMBERS), 6)
        self.assertFalse(any('Helper' in f for f in MEMBERS))

    def test_cannot_forge_checked_driver_or_sds_receipts_in_recovery_fixture(self):
        check = source('tests/windows/check_interrupted_recovery.ps1')
        for marker in ('forged-stage-receipt-denied', 'forged-sds-marker-denied',
                       'forged_receipts_denied',
                       'No exact exclusive VBoxSup staging receipt',
                       'SDS marker owner differs'):
            self.assertIn(marker, check)

    def test_real_host_breaks_after_three_actual_checkpoints(self):
        check = source('tests/windows/check_interrupted_recovery.ps1')
        workflow = source('.github/workflows/interrupted-recovery.yml')
        for phase in ('Stage', 'Start', 'Sds'):
            self.assertIn(phase, check)
        for key in ('missing-receipt-denied', 'live-owner-denied',
                    'PartialRecovery', 'after-recovery-clean', 'two_copies',
                    'original_data_preserved', 'PVBOX_TEST_BREAK_AT'):
            self.assertIn(key, check)
        self.assertIn('check_interrupted_recovery.ps1', workflow)
        self.assertIn('windows-2022', workflow)
        self.assertIn('actions/upload-artifact@', workflow)

if __name__ == '__main__':
    unittest.main()
