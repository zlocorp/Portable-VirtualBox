"""Main compiled launcher must reuse real Manager session, not another diagnostic counter."""
from pathlib import Path
import unittest

R=Path(__file__).resolve().parents[1]

class MainManagerWiring(unittest.TestCase):
    def test_main_gui_opens_actual_session_controller_with_fail_closed_gate(self):
        gui=(R/'source/LauncherGui.au3').read_text(encoding='utf-8-sig')
        self.assertIn('#include "ManagerWindow.au3"',gui)
        self.assertIn('GUICtrlCreateButton("", 346, 492, 310, 37)',gui)
        self.assertIn('_MS_Allowed(@ScriptDir, EnvGet("GITHUB_WORKSPACE"))',gui)
        self.assertIn('_MSW_Show(@ScriptDir, EnvGet("GITHUB_WORKSPACE"))',gui)
        self.assertIn('$g_MS_Separated = _PB_Medium()',gui)
        self.assertIn('GUICtrlSetState($idManager, $GUI_DISABLE)',gui)
        self.assertIn('Case $idManager',gui)
        self.assertNotIn('ProcessClose(',gui)
    def test_main_gui_has_localized_user_control(self):
        gui=(R/'source/LauncherGui.au3').read_text(encoding='utf-8-sig')
        lang=(R/'source/LauncherI18n.au3').read_text(encoding='utf-8-sig')
        self.assertIn('_LI("gui.manager")',gui)
        self.assertIn('Case "gui.manager"',lang)
    def test_main_gui_click_is_bounded_and_reports_real_disabled_gate(self):
        s=(R/'scripts/check_manager_session_gui.ps1').read_text(encoding='utf-8')
        self.assertIn('function Wait-MainButton(',s)
        self.assertIn('Main launcher Start/Stop disabled by safety gate',s)
        self.assertIn('Main launcher button not visible after',s)
        self.assertIn('Wait-MainButton $Process',s)

    def test_ci_effect_worker_binds_both_exact_compiled_controller_images(self):
        worker=(R/'scripts/manager_session_worker.ps1').read_text(encoding='utf-8')
        self.assertIn("(Join-Path $root 'Portable-VirtualBox.exe')",worker)
        self.assertIn("(Join-Path $root 'Portable-VirtualBox-Session-Test.exe')",worker)
        self.assertIn('$parentPath -notin @(',worker)
        self.assertNotIn("if ($parentPath -ine (Join-Path $root 'Portable-VirtualBox-Session-Test.exe'))",worker)

    def test_manager_cleanup_accepts_only_the_two_exact_controller_images(self):
        cleanup=(R/'scripts/vbox_sup_cleanup.ps1').read_text(encoding='utf-8')
        self.assertIn("(Join-Path $proof.portable_root 'Portable-VirtualBox.exe')",cleanup)
        self.assertIn("(Join-Path $proof.portable_root 'Portable-VirtualBox-Session-Test.exe')",cleanup)
        self.assertIn('$controller.MainModule.FileName -notin $approvedControllers',cleanup)
        self.assertNotIn("$controller.MainModule.FileName -ine (Join-Path $proof.portable_root 'Portable-VirtualBox-Session-Test.exe')",cleanup)

    def test_main_gui_fixture_has_real_portable_disk_and_snapshot(self):
        script=(R/'scripts/check_manager_session_gui.ps1').read_text(encoding='utf-8')
        for term in ('createmedium disk', 'storagectl ', 'storageattach ', 'showmediuminfo disk',
                     'take portable-baseline', 'snapshot_preserved_after_cleanup=$true',
                     'disk_preserved_after_cleanup=$true'):
            self.assertIn(term, script)

    def test_unattended_runas_reaches_real_main_gui_without_false_approval(self):
        workflow=(R/'.github/workflows/privilege-session.yml').read_text(encoding='utf-8')
        fixture=(R/'scripts/check_manager_session_gui.ps1').read_text(encoding='utf-8')
        self.assertIn('build/Portable-VirtualBox_x64.exe', workflow)
        self.assertIn('build_session_helper.ps1 -Frontend $exe', workflow)
        self.assertIn('-MainLauncher -SeparatePrivileges -UnattendedConsentProbe', workflow)
        self.assertIn('main_uac_request_pending=[bool]$MainLauncher', fixture)
        self.assertIn('unattended_ui_responsive=$true', fixture)
        self.assertIn('interactive_uac_consent_verified=$false', fixture)

    def test_alpha_mode_is_explicit_and_does_not_enable_normal_launch(self):
        entry=(R/'source/Portable-VirtualBox.au3').read_text(encoding='utf-8-sig')
        session=(R/'source/ManagerSession.au3').read_text(encoding='utf-8-sig')
        for needle in ('Case "--alpha-runtime"', 'Case "--elevation-worker", "--alpha-elevation-worker"',
                       '$g_MS_AlphaMode = True', '_MS_Allowed(@ScriptDir'):
            self.assertIn(needle, entry)
        for needle in ('Func _MS_AlphaPolicy(', 'Func _MS_AlphaAllowed(', '_PB_Medium()',
                       'Portable-VirtualBox-Helper-Alpha.exe', 'If $g_MS_AlphaMode Then Return _MS_AlphaAllowed'):
            self.assertIn(needle, session)
        self.assertIn('Portable-VirtualBox-Helper-Alpha.exe', (R/'source/PrivilegeBoundary.au3').read_text(encoding='utf-8-sig'))

    def test_alpha_build_does_not_change_standard_diagnostic_zip(self):
        from pathlib import Path
        source=(R/'source/Portable-VirtualBox.au3').read_text(encoding='utf-8-sig')
        self.assertIn('Case "--alpha-runtime"',source)
        build=(R/'scripts/package_preview.py').read_text(encoding='utf-8-sig')
        self.assertNotIn('Portable-VirtualBox-Helper-Alpha.exe',build)
        self.assertIn('alpha-runtime', (R/'docs/ALPHA-WINDOWS-TEST.md').read_text(encoding='utf-8'))

    def test_real_guest_iso_uses_same_main_gui_and_preserves_visual_evidence(self):
        workflow=(R/'.github/workflows/manager-session.yml').read_text(encoding='utf-8')
        fixture=(R/'scripts/check_manager_session_gui.ps1').read_text(encoding='utf-8')
        self.assertIn('alpine-virt-3.24.3-x86_64.iso', workflow)
        self.assertIn('Get-FileHash -LiteralPath $iso -Algorithm SHA256', workflow)
        self.assertIn('-MainLauncher -GuestIso $env:MANAGER_GUEST_ISO', workflow)
        for phrase in ('attach-guest-iso', '--boot1 dvd', 'guest-boot-alpine.png',
                       'screenshotpng', 'guest_screen_capture=$true', 'GuestIsoSha256'):
            self.assertIn(phrase, fixture)
        self.assertIn('guest_os_booted=$false', fixture)
        self.assertIn("'Linux_64'", fixture)
        self.assertIn('--x86-long-mode on', fixture)
        self.assertIn('longmode="on"', fixture)
        self.assertIn('guest_64bit_cpu_configured=$true', fixture)
        self.assertIn('closemedium dvd',fixture)
        self.assertIn('eject-external-ci-iso',fixture)
        for expected in ('keyboardputstring root', 'keyboardputscancode 1c 9c',
                         'dd of=/dev/sda bs=512 seek=2048 conv=notrunc',
                         'clonemedium disk', 'guest_disk_io_confirmed=$true',
                         'No guest-written VDI sector marker',
                         'guest-disk-command.png'):
            self.assertIn(expected, fixture)
        self.assertIn('Remove-Item -LiteralPath $raw', fixture)
        self.assertIn('retention-days: 7', workflow)

    def test_real_compiled_rebind_uses_actual_gui_dialog_and_safe_backup(self):
        s=(R/'scripts/check_manager_session_gui.ps1').read_text(encoding='utf-8')
        for token in ('Repair moved VM','Wait-Dialog', 'ChooseFolder',
                      'rebind_backup_verified=$true', 'rebind_gui_confirmed=$true',
                      'rebind_owned_cleanup=$true', 'rebind_snapshot_verified=$true',
                      'REBIND_UNREGISTER', 'REBIND_REGISTER', 'Assert-Clean'):
            self.assertIn(token,s)
        self.assertIn("Snapshot",s)
        self.assertNotIn('unregistervm --delete',s)

    def test_windows_uses_main_exe_to_prove_real_start_stop(self):
        w=(R/'.github/workflows/manager-session.yml').read_text(encoding='utf-8')
        s=(R/'scripts/check_manager_session_gui.ps1').read_text(encoding='utf-8')
        self.assertIn('build/Portable-VirtualBox_x64.exe',w)
        self.assertIn("ArgumentList '--version'",w)
        self.assertNotIn('$p=Start-Process -FilePath $exe -PassThru -Wait -NoNewWindow',w)
        self.assertIn("ArgumentList '--version'",w)
        self.assertNotIn("$p=Start-Process -FilePath $exe -PassThru -Wait -NoNewWindow",w)
        self.assertIn('-MainLauncher',w)
        self.assertIn('[switch]$MainLauncher',s)
        self.assertIn('Open-SessionWindow',s)
        self.assertIn('Click-Button $front',s)

if __name__=='__main__':unittest.main()
