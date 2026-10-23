"""Source/packaging contracts supplement, not replace, real Windows execution."""
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]

class PrivilegeBoundaryContract(unittest.TestCase):
    def text(self, name):
        p = ROOT / name
        self.assertTrue(p.is_file(), 'Missing privilege-boundary implementation: ' + name)
        return p.read_text(encoding='utf-8-sig')

    def test_two_actions_no_untrusted_command_or_script_arguments(self):
        s = self.text('source/privilege/SessionHelper.cs') + self.text('source/privilege/SessionHelper.Main.cs')
        for expected in ('Prepare', 'Finish', 'VerifyController', 'CreateProtectedDirectory', 'FileShare.Read', 'GetManifestResourceStream'):
            self.assertIn(expected, s)
        self.assertNotIn('Arguments = args[', s)
        self.assertIn('FrontendSha256', s)

    def test_elevation_retains_native_handle_and_distinguishes_cancel(self):
        s = self.text('source/PrivilegeBoundary.au3')
        for expected in ('ShellExecuteExW', 'runas', '1223', 'CANCELLED', 'handle process', 'GetProcessId'):
            self.assertIn(expected, s)
        self.assertNotIn('#RequireAdmin', s)

    def test_trusted_inventory_matches_verified_package(self):
        text = self.text('source/privilege/oracle-7.2.22-pin.json')
        j = json.loads(text)
        self.assertEqual(j['file_count'], 185)
        self.assertEqual(j['total_bytes'], 247834716)
        self.assertEqual(j['installer_sha256'], 'afd0ff1656cbe04ed88ce619594ae021419d97cce89fa9bdc443e9a963f1713f')
        self.assertRegex(j['manifest_rows_sha256'], r'^[0-9a-f]{64}$')
        self.assertIn('CanonicalInventorySha256', self.text('source/privilege/SessionHelper.cs'))
        self.assertIn('PinnedBuild.InventorySha256', self.text('source/privilege/SessionHelper.cs'))

    def test_configuration_not_performed_as_admin(self):
        worker = self.text('scripts/privileged_session_worker.ps1')
        self.assertNotIn('setproperty machinefolder', worker)
        self.assertIn('--regservice', worker)
        s = self.text('source/ManagerSession.au3')
        self.assertIn('CONFIGURING', s)
        self.assertIn('setproperty machinefolder', s)
        self.assertIn('CLEANUP_DECLINED', s)

    def test_medium_fixture_can_lower_its_restricted_token(self):
        # CreateRestrictedToken preserves handle access rights. Lowering the
        # integrity label requires TOKEN_ADJUST_DEFAULT, not a more privileged
        # child token. The real Windows workflow proves the resulting token.
        import re
        s = self.text('tests/windows/MediumProcess.cs')
        rights = re.search(r'OpenProcessToken\(GetCurrentProcess\(\),0x([0-9A-Fa-f]+),out old\)', s)
        self.assertIsNotNone(rights)
        self.assertEqual(int(rights.group(1), 16) & 0x008B, 0x008B)
        self.assertIn('LastFacts.Administrator || LastFacts.Integrity!=8192', s)

    def test_principal_membership_observer_has_duplicate_right(self):
        # WindowsPrincipal.IsInRole duplicates a primary token for the native
        # membership query. QUERY alone raises SecurityException, even for the
        # freshly created suspended child. This does not adjust token groups.
        s = self.text('source/privilege/TokenFacts.cs')
        self.assertIn('OpenProcessToken(p,0x000A,out t)', s)
        self.assertIn('WindowsPrincipal(id).IsInRole', s)

    def test_portable_fixture_is_owned_by_the_exact_user_not_the_admin_group(self):
        workflow = self.text('.github/workflows/privilege-session.yml')
        self.assertIn('tests/windows/Set-PortableFixtureOwner.ps1', workflow)
        fixture = self.text('tests/windows/Set-PortableFixtureOwner.ps1')
        self.assertIn('WindowsIdentity]::GetCurrent().User', fixture)
        self.assertIn('FileSystemRights]::Modify', fixture)
        self.assertIn('ReparsePoint', fixture)
        self.assertIn('RUNNER_TEMP', fixture)
        self.assertNotIn('CommonApplicationData', fixture)

    def test_direct_helper_fixture_does_not_claim_uac_acceptance(self):
        workflow = self.text('.github/workflows/helper-boundary.yml')
        self.assertIn('tests/windows/check_helper_boundary.ps1', workflow)
        fixture = self.text('tests/windows/check_helper_boundary.ps1')
        self.assertIn('gui_runas_verified=$false', fixture)
        self.assertIn('interactive_uac_consent_verified=$false', fixture)
        self.assertIn('ProtectedWriteProbe.cs', fixture)
        self.assertIn("Helper-Action Finish $cycle 70", fixture)
        self.assertNotIn('EnableLUA', fixture)

    def test_manager_and_cli_use_the_validated_protected_runtime(self):
        s = self.text('source/ManagerSession.au3')
        self.assertIn('_MP_Start($s["app_system"] & "\\VirtualBox.exe"', s)
        self.assertIn('_MP_Start($s["app_system"] & "\\VBoxManage.exe"', s)
        self.assertNotIn('_MP_Start($profile["app"]', s)
        # Only code moves to the protected cache; profile and VM data stay with
        # the ordinary user's portable root and do not acquire admin ownership.
        self.assertIn('$profile["profile"]', s)
        self.assertIn('$profile["machines"]', s)

    def test_async_uac_pending_is_not_mistaken_for_a_timed_out_helper(self):
        session = self.text('source/ManagerSession.au3')
        for marker in ('Func _MS_ConsentPhase(', 'Func _MS_ConsentPending(',
                       'CONSENT_PREPARE', 'CONSENT_FINISH',
                       '_MS_ConsentPhase($s["separated"], "Prepare")',
                       '_MS_ConsentPhase($s["separated"], "Finish")',
                       'Not _MS_ConsentPending($state) And TimerDiff'):
            self.assertIn(marker, session)
        gui = self.text('source/ManagerWindow.au3')
        for marker in ('Case "CONSENT_PREPARE"', 'Case "CONSENT_FINISH"'):
            self.assertIn(marker, gui)
        script = self.text('scripts/check_manager_session_gui.ps1')
        for marker in ('UnattendedConsentProbe', "Await-State $badFront 'CONSENT_PREPARE'",
                       'interactive_uac_consent_verified=$false',
                       'unattended_ui_responsive=$true'):
            self.assertIn(marker, script)
        self.assertNotIn('EnableLUA', script)

    def test_helper_not_in_preview(self):
        import sys
        sys.path.insert(0,str(ROOT / 'scripts'))
        import package_preview
        self.assertEqual(len(package_preview.MEMBERS), 7)
        self.assertFalse(any('Helper' in p or 'Session-Test' in p for p in package_preview.MEMBERS))

if __name__ == '__main__': unittest.main()
