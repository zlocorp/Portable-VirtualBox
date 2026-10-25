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
