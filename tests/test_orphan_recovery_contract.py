"""Fail-closed abandoned-session recovery: static contracts supplement real Windows tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(name):
    return (ROOT / name).read_text(encoding='utf-8-sig')


class OrphanRecovery(unittest.TestCase):
    def test_fixed_helper_accepts_only_explicit_numeric_recover_and_rechecks_owner(self):
        src = read('source/privilege/SessionHelper.Main.cs')
        for needle in ('"Recover"', 'OrphanControllerAbsent', 'VerifyOriginalSession',
                       'PinnedBuild.FrontendSha256', 'OriginalControllerPid',
                       'Untrusted or ambiguous recovery target'):
            self.assertIn(needle, src)
        self.assertNotIn('Environment.GetEnvironmentVariable("RECOVERY_PATH")', src)

    def test_recovery_reuses_exact_receipts_and_existing_cleanup(self):
        script = read('scripts/privileged_session_worker.ps1')
        for needle in ('Recover', 'recovery-quiescent.json', 'orphan-manager-quiescent',
                       'vbox_sup_cleanup.ps1', '-RecoveryReport', 'OriginalControllerCreated',
                       'Test-OriginalControllerAbsent'):
            self.assertIn(needle, script)
        cleanup = read('scripts/vbox_sup_cleanup.ps1')
        for needle in ('ParameterSetName="RecoverySession"', 'RecoveryReport',
                       'orphan-manager-quiescent', 'Test-OriginalControllerAbsent',
                       'Protected cleanup recovery proof'):
            self.assertIn(needle, cleanup)
        self.assertIn('Get-VBoxProcesses', cleanup)
        self.assertIn('Get-VBoxNames', cleanup)

    def test_orphan_recovery_requires_explicit_button_and_keeps_diagnostic_zip_clean(self):
        src = read('source/ManagerSession.au3')
        self.assertIn('Func _MS_Recover', src)
        self.assertIn('Func _MS_FindRecoverable', src)
        self.assertIn('CONSENT_RECOVER', src)
        self.assertIn('$s["state"] <> "BLOCKED"', src)
        self.assertIn('RECOVERING', src)
        gui = read('source/ManagerWindow.au3')
        self.assertIn('Recover abandoned session', gui)
        self.assertIn('CONSENT_RECOVER', gui)
        launcher = read('source/Portable-VirtualBox-Session-Test.au3')
        self.assertIn('--elevation-worker', launcher)
        self.assertIn('Recover', launcher)
        ordinary = read('source/Portable-VirtualBox.au3')
        self.assertNotIn('Recover abandoned session', ordinary)
        import sys
        sys.path.insert(0, str(ROOT / 'scripts'))
        from package_preview import MEMBERS
        self.assertEqual(len(MEMBERS), 7)

    def test_windows_fixture_uses_real_driver_and_rejects_live_or_foreign_recovery(self):
        workflow = read('.github/workflows/orphan-recovery.yml')
        self.assertIn('check_orphan_recovery.ps1', workflow)
        fixture = read('tests/windows/check_orphan_recovery.ps1')
        self.assertIn('function Start-Medium([string]$Image,[string]$Arguments', fixture)
        self.assertNotIn('[string]$Args,', fixture)
        for needle in ('live-owner-refusal', 'live-guest-refusal',
                       'Recover', 'cleanup_verified', 'payload-removed.json',
                       'live-owner-refusal', 'Original VM data changed during recovery'):
            self.assertIn(needle, fixture)


if __name__ == '__main__':
    unittest.main()
