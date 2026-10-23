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
