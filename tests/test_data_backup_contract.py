"""Public backup must be a real compiled, non-elevated workflow."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DataBackupContract(unittest.TestCase):
    def test_public_cli_and_gui_both_wire_real_backend(self):
        entry = (ROOT / 'source/Portable-VirtualBox.au3').read_text(encoding='utf-8-sig')
        gui = (ROOT / 'source/LauncherGui.au3').read_text(encoding='utf-8-sig')
        backend = (ROOT / 'source/PortableDataBackup.au3').read_text(encoding='utf-8-sig')
        self.assertIn('Case "--backup-data", "--verify-backup"', entry)
        self.assertIn('_PBK_Create(@ScriptDir, $backupPath)', entry)
        self.assertIn('_PBK_Verify($backupPath)', entry)
        self.assertIn('Case $idBackup, $idVerify', gui)
        self.assertIn('_MP_Start(@ScriptFullPath, $args, @ScriptDir)', gui)
        self.assertIn('Case $idCancel', gui)
        for marker in ('_PBK_Offline()', '_PBK_GrabSessionLock()',
                       'MapExists($rows, $key)', '_PBK_VerifyInternal($pending)',
                       'MoveFileExW', 'SHA256SUMS.txt', 'FileCopy(',
                       'FileFindFirstFile(', '_Crypt_HashFile', 'RUNNER_TEMP'):
            if marker == 'RUNNER_TEMP':
                self.assertNotIn(marker, backend, "backup must not require CI environment")
            else:
                self.assertIn(marker, backend)
        self.assertNotIn('#RequireAdmin', backend)
        self.assertNotIn('DirRemove(', backend)
        self.assertNotIn('ProcessClose(', backend)

    def test_locales_and_windows_ci_coverage(self):
        gui = (ROOT/'source/LauncherGui.au3').read_text(encoding='utf-8-sig')
        catalog = (ROOT/'source/LauncherI18n.au3').read_text(encoding='utf-8-sig')
        for k in ('backup.create','backup.verify','backup.cancel','backup.blocked',
                  'backup.failed','backup.verified','backup.hint'):
            self.assertIn(f'Case "{k}"', catalog)
        self.assertIn('GUICtrlCreateEdit', gui)
        self.assertTrue((ROOT/'tests/native/test_portable_data_backup.au3').is_file())
        workflow = (ROOT/'.github/workflows/ci.yml').read_text(encoding='utf-8')
        self.assertIn('Offline portable data backup', workflow)
        fixture = (ROOT/'scripts/check_offline_backup.ps1').read_text(encoding='utf-8')
        self.assertIn('--verify-backup', fixture)
        self.assertIn('--backup-data', fixture)


if __name__ == '__main__':
    unittest.main()
