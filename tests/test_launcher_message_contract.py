"""Presentation wiring contracts, not native execution or Windows GUI acceptance."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(name):
    return (ROOT / "source" / name).read_text(encoding="utf-8-sig")


class LauncherMessageContract(unittest.TestCase):
    def test_backup_verification_does_not_claim_a_new_copy(self):
        catalog = source("LauncherI18n.au3")
        verified = catalog.split('Case "backup.verified"', 1)[1].split("Case ", 1)[0]
        self.assertNotRegex(verified.lower(), r"created|создан")
        for key in ("backup.created", "backup.verifying", "backup.restoring"):
            self.assertIn(f'Case "{key}"', catalog)
        entry = source("Portable-VirtualBox.au3")
        verify = entry.split('If $CmdLine[$iFirst] == "--verify-backup" Then', 1)[1].split('Local $risk', 1)[0]
        create = entry.split('Local $backupResult = _PBK_Create', 1)[1].split('Case "--plan-vm-rebind"', 1)[0]
        self.assertIn('_LI("backup.verified")', verify)
        self.assertNotIn('_LI("backup.created")', verify)
        self.assertIn('_LI("backup.created")', create)
        self.assertNotIn('_LI("backup.verified")', create)

    def test_gui_uses_action_specific_backup_presentation(self):
        gui = source("LauncherGui.au3")
        self.assertIn('$backupMessageKey = _LG_BackupProgressKey($backupAction)', gui)
        self.assertIn('$message = _LG_BackupSuccessKey($backupAction)', gui)

    def test_gui_passes_existing_alpha_flag_only_to_presentation(self):
        gui = source("LauncherGui.au3")
        self.assertIn('_PortableDiagnosticCollect($g_MS_AlphaMode)', gui)
        self.assertIn('_LA_Text("", $g_MS_AlphaMode)', gui)
        calls = re.findall(r'_LR_Inspect\(([^\n]+?)\)', gui)
        self.assertEqual(calls, ['@ScriptDir, $g_MS_AlphaMode'] * 3)
        catalog = source("LauncherI18n.au3")
        for key in ("app.alpha_runtime", "diag.runtime_alpha", "readiness.alpha"):
            self.assertIn(f'Case "{key}"', catalog)


if __name__ == "__main__":
    unittest.main()
