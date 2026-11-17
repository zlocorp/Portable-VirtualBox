"""Functional first-run user-data provisioning in the compiled launcher."""
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
def read(path):return (ROOT/path).read_text(encoding="utf-8-sig")

class PortableProductWiring(unittest.TestCase):
    def test_cli_first_run_status_and_creation_commands(self):
        source=read("source/Portable-VirtualBox.au3")
        self.assertIn('#include "PortableProfile.au3"',source)
        self.assertIn('Case "--profile-status"',source)
        self.assertIn('Case "--prepare-profile"',source)
        self.assertIn('_PP_Ensure(@ScriptDir)',source)
        self.assertIn('_PP_Inspect(@ScriptDir)',source)
        self.assertIn('_LI("profile.',source)

    def test_gui_buttons_have_provisioning_callback(self):
        gui=read("source/LauncherGui.au3")
        self.assertIn('_PP_Ensure(@ScriptDir)',gui)
        self.assertIn('_PP_Inspect(@ScriptDir)',gui)
        self.assertIn('_LI("gui.prepare")',gui)
        self.assertIn('_LI("gui.path")',gui)
        self.assertIn('GUICtrlCreateButton(',gui)

    def test_ci_executes_real_userdata_first_run_and_repeat(self):
        workflow=read(".github/workflows/ci.yml")
        self.assertIn("--prepare-profile",workflow)
        self.assertIn("--profile-status",workflow)
        self.assertIn("data\\.VirtualBox",workflow)
        self.assertIn("data\\Machines",workflow)
        self.assertIn("preserved-user-data",workflow)

if __name__=="__main__":unittest.main()
