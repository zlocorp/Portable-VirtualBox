"""Product-facing launcher behavior contract; no driver launch in active entrypoint."""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[1]

class ProductLauncherContracts(unittest.TestCase):
    def test_launcher_has_interactive_readonly_diagnostic_ui(self):
        src=(ROOT/"source/Portable-VirtualBox.au3").read_text(encoding="utf-8-sig")
        gui=(ROOT/"source/LauncherGui.au3").read_text(encoding="utf-8-sig")
        self.assertIn('#include "LauncherI18n.au3"',src)
        self.assertIn('#include "LauncherGui.au3"',src)
        self.assertIn("Case \"--help\"",src)
        self.assertIn("_LG_Show()",src)
        self.assertIn("GUICreate(",gui)
        self.assertIn("GUICtrlCreateEdit(",gui)
        self.assertIn("ClipPut(",gui)
        self.assertIn('Case "--diagnose"',src)
        for pattern in (r"(?i)\bRun(?:Wait)?\s*\(",r"(?i)\bProcessClose\s*\(",r"(?i)\bRegWrite\s*\("):
            self.assertNotRegex(gui,pattern)
        self.assertNotIn('#RequireAdmin',"\n".join(l for l in src.splitlines() if not l.strip().startswith(";")))

    def test_host_diagnostics_uses_shared_localization(self):
        s=(ROOT/"source/HostDiagnostics.au3").read_text(encoding="utf-8-sig")
        self.assertIn("_LI(",s)
        self.assertIn("Func _PortableDiagnosticCollect",s)
        self.assertIn("Func _PortableDiagnosticWrite",s)

if __name__=="__main__":
    unittest.main()
