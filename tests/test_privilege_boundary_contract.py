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
        self.assertIn('PinnedBuild.FrontendName', s)
        for path in ('scripts/vbox_sup_cleanup.ps1', 'scripts/vbox_sup_partial_cleanup.ps1'):
            cleanup = self.text(path)
            self.assertIn("controller_image -notin @(", cleanup)
            self.assertIn("Portable-VirtualBox-Session-Test.exe", cleanup)
            self.assertIn("Portable-VirtualBox.exe", cleanup)
        self.assertIn('" -FrontendName "+PinnedBuild.FrontendName', s)

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

    def test_exact_main_frontend_binding_stays_ci_only(self):
        compiler = self.text('scripts/build_session_helper.ps1')
        self.assertIn("Portable-VirtualBox_x64.exe", compiler)
        self.assertIn("internal const string FrontendName", compiler)
        worker = self.text('scripts/privileged_session_worker.ps1')
        self.assertIn("ValidateSet('Portable-VirtualBox.exe','Portable-VirtualBox-Session-Test.exe')", worker)
        self.assertIn('(Join-Path $root $FrontendName)', worker)
        entry = self.text('source/Portable-VirtualBox.au3')
        self.assertIn('Case "--elevation-worker"', entry)
        self.assertIn('If Not _MS_Allowed(@ScriptDir', entry)
        self.assertIn('_PB_RunRequest(@ScriptDir', entry)
        gui = self.text('source/LauncherGui.au3')
        self.assertIn('$g_MS_Separated = _PB_Medium()', gui)
        workflow = self.text('.github/workflows/helper-boundary.yml')
        self.assertIn('frontend: [session-test, main-launcher]', workflow)
        self.assertIn("-MainLauncher:", workflow)

    def test_no_orphaned_privileged_child_on_elapsed_timeout(self):
        helper=self.text('source/privilege/SessionHelper.Main.cs')
        self.assertIn('bool withinDeadline=process.WaitForExit(150000)', helper)
        self.assertIn('if(!withinDeadline) process.WaitForExit()', helper)
        self.assertIn('if(!withinDeadline) throw new InvalidOperationException', helper)
        self.assertIn('Environment.SystemDirectory,"WindowsPowerShell","v1.0","powershell.exe"', helper)
        self.assertNotIn('"PowerShell","7","pwsh.exe"', helper)
        worker=self.text('source/PrivilegeBoundary.au3')
        self.assertIn('While 1', worker)
        self.assertIn('$controllerPresent', worker)
        self.assertNotIn('While TimerDiff($clock) < 180000', worker)

    def test_built_in_powershell_retains_command_process_handles(self):
        for path, variable in (
            ('scripts/vbox_sup_standalone.ps1', 'process'),
            ('scripts/vbox_sup_start_owned.ps1', 'proc'),
            ('scripts/vbox_sup_cleanup.ps1', 'p'),
            ('scripts/vbox_sup_partial_cleanup.ps1', 'p'),
            ('scripts/privileged_session_worker.ps1', 'p')
        ):
            contents = self.text(path)
            self.assertIn('$ownedHandle', contents)
            self.assertIn('$' + variable + '.Handle', contents)
            self.assertIn('WaitForExit(', contents)

    def test_privileged_native_commands_never_detach_or_kill_on_timeout(self):
        fixtures = (
            ('scripts/vbox_sup_standalone.ps1', '$process'),
            ('scripts/vbox_sup_start_owned.ps1', '$proc'),
            ('scripts/vbox_sup_cleanup.ps1', '$p'),
            ('scripts/vbox_sup_partial_cleanup.ps1', '$p'),
            ('scripts/privileged_session_worker.ps1', '$p'),
        )
        for path, child in fixtures:
            source=self.text(path)
            self.assertIn(child+'.WaitForExit()', source, path)
            self.assertIn('WaitForExit(', source, path)
            self.assertNotIn(child+'.Kill()', source, path)
            self.assertNotIn('Stop-Process', source, path)
            self.assertNotIn('taskkill', source, path)
        for path in ('scripts/vbox_sup_standalone.ps1', 'scripts/vbox_sup_start_owned.ps1'):
            self.assertIn("status = 'TIMEOUT'" if 'standalone' in path else "status='TIMEOUT'",self.text(path))

    def test_medium_main_helper_guest_io_after_protected_teardown(self):
        workflow=self.text('.github/workflows/helper-boundary.yml')
        fixture=self.text('tests/windows/check_helper_boundary.ps1')
        for marker in ('GuestIsoSha256','guest_disk_survived_teardown=$false',
                       'PVBOX_PROTECTED_MEDIUM_GUEST_WRITE_20261027',
                       'keyboardputstring', 'clonemedium disk',
                       'guest_snapshot_preserved=$true', 'Remove-Item -LiteralPath $raw'):
            self.assertIn(marker,fixture)
        self.assertIn('GuestIsoSha256', workflow)
        self.assertIn('main-launcher',workflow)
        self.assertIn('retention-days: 7',workflow)

    def test_inbox_powershell_required_in_effect_worker(self):
        s=self.text('scripts/privileged_session_worker.ps1')
        self.assertIn("$PSVersionTable.PSEdition -ne 'Desktop'", s)
        self.assertIn('$PSVersionTable.PSVersion.Major -ne 5', s)
        workflow=self.text('.github/workflows/helper-boundary.yml')
        self.assertIn('Require native Windows PowerShell 5.1', workflow)

    def test_protected_receipts_decode_unicode_consistently_on_windows_powershell(self):
        for path in (
            'scripts/privileged_session_worker.ps1',
            'scripts/vbox_sup_partial_cleanup.ps1',
            'scripts/vbox_sup_cleanup.ps1',
            'scripts/vbox_sup_start_owned.ps1'
        ):
            source=self.text(path)
            matches=[line for line in source.splitlines()
                     if 'Get-Content ' in line and '| ConvertFrom-Json' in line]
            self.assertTrue(matches, path)
            for line in matches:
                self.assertIn('-Encoding UTF8', line, path)

    def test_alpha_store_is_not_ci_experiment_store(self):
        adapter=self.text('source/PrivilegeBoundary.au3')
        self.assertIn('PortableVirtualBox.Alpha',adapter)
        self.assertIn('PortableVirtualBox.Experiment',adapter)
        self.assertIn('--alpha-elevation-worker',adapter)
        self.assertIn('_PB_HelperName()',adapter)

    def test_interactive_candidate_is_compile_time_pinned_and_workstation_only(self):
        build=self.text('scripts/build_session_helper.ps1')
        helper=self.text('source/privilege/SessionHelper.Main.cs')
        for key in ('[switch]$AlphaCandidate','Portable-VirtualBox-Helper-Alpha.exe',
                    'internal const string Mode','internal const string HelperName'):
            self.assertIn(key,build)
        for key in ('PinnedBuild.Mode=="CI"','PinnedBuild.Mode=="ALPHA"',
                    'PinnedBuild.HelperName', 'WorkstationAlphaHost()',
                    'v.Build>=19041 && v.Product==1','PVBOX_FIXED_HELPER_MODE',
                    'PortableVirtualBox.Alpha'):
            self.assertIn(key,helper)
        self.assertIn('string testBreak=(PinnedBuild.Mode=="CI"',helper)

    def test_candidate_effects_run_only_under_a_verified_protected_worker(self):
        worker=self.text('scripts/privileged_session_worker.ps1')
        for phrase in ('Assert-PortableFixedHelper','Candidate helper/frontend pair mismatched',
                       'PortableVirtualBox.Alpha', 'Portable-VirtualBox-Helper-Alpha.exe',
                       "PVBOX_FIXED_HELPER_MODE -eq 'ALPHA'", 'Get-CimInstance Win32_OperatingSystem'):
            self.assertIn(phrase,worker)
        for p in ('scripts/vbox_sup_standalone.ps1',
                  'scripts/vbox_sup_start_owned.ps1',
                  'scripts/vbox_sup_cleanup.ps1',
                  'scripts/vbox_sup_partial_cleanup.ps1'):
            source=self.text(p)
            self.assertIn("PVBOX_FIXED_HELPER_MODE -eq 'ALPHA'", source)
            self.assertIn('Assert-PortableFixedHelper', source)
            self.assertIn("GITHUB_ACTIONS -ne 'true'", source)

    def test_nonrelease_alpha_bundle_requires_pinned_main_and_notices(self):
        p=self.text('scripts/package_alpha.ps1')
        for value in ('Portable-VirtualBox-Helper-Alpha.exe','Portable-VirtualBox-Setup.exe',
                      'SHA256SUMS.txt','ALPHA-TEST-ONLY.md','FrontendSha256'):
            self.assertIn(value,p)
        self.assertNotIn('app64',p)
        wf=self.text('.github/workflows/alpha-candidate.yml')
        for value in ('workflow_dispatch','-AlphaCandidate','Win10-11-ALPHA-TEST-ONLY',
                      'Windows Server', 'retention-days: 7'):
            self.assertIn(value,wf)
        instructions=self.text('docs/ALPHA-WINDOWS-TEST.md')
        self.assertIn('--alpha-runtime',instructions)
        self.assertIn('not a stable',instructions)

    def test_helper_not_in_preview(self):
        import sys
        sys.path.insert(0,str(ROOT / 'scripts'))
        import package_preview
        self.assertEqual(len(package_preview.MEMBERS), 7)
        self.assertFalse(any('Helper' in p or 'Session-Test' in p for p in package_preview.MEMBERS))

if __name__ == '__main__': unittest.main()
