"""Locale-independent exact-owned OEM package receipts; no driver mutations here."""
from pathlib import Path
import os
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('powershell.exe') or shutil.which('pwsh')

class DriverPackageIdentity(unittest.TestCase):
    def test_cleanup_never_uses_localized_pnputil_transcripts_as_authority(self):
        for name in ('vbox_sup_cleanup.ps1', 'vbox_sup_partial_cleanup.ps1'):
            text = (ROOT / 'scripts' / name).read_text(encoding='utf-8')
            self.assertNotIn('Published Name:', text)
            self.assertNotIn('$installText', text)
            self.assertIn('Get-PortableOwnedPublishedInf', text)
            self.assertIn("'vbox_sup_package_identity.ps1'", text)

    def test_staging_binds_new_name_and_hash_before_committing_receipt(self):
        text = (ROOT / 'scripts/vbox_sup_standalone.ps1').read_text(encoding='utf-8')
        self.assertIn('Get-PortableNewPublishedInf', text)
        self.assertIn('Get-PortablePublishedInfFiles', text)
        for field in ('published_inf_schema', 'published_inf', 'published_inf_sha256',
                      'published_inf_was_absent'):
            self.assertIn(field, text)
        self.assertLess(text.index('Get-PortablePublishedInfFiles'), text.index('Start-Process'))
        self.assertLess(text.index('Get-PortableNewPublishedInf'), text.index("sup-standalone.json"))

    def test_shared_readonly_identity_is_embedded_and_windows_behavior_is_executed(self):
        for path in ('scripts/build_session_helper.ps1', 'source/privilege/SessionHelper.cs'):
            self.assertIn('vbox_sup_package_identity.ps1', (ROOT / path).read_text(encoding='utf-8'))
        workflow = (ROOT / '.github/workflows/native-tests.yml').read_text(encoding='utf-8')
        self.assertIn('check_driver_package_identity.ps1', workflow)
        self.assertIn('shell: powershell', workflow)

    @unittest.skipUnless(POWERSHELL, 'Actual PowerShell identity functions require PowerShell')
    def test_native_package_identity_behavior(self):
        shell = POWERSHELL
        self.assertIsNotNone(shell)
        result = subprocess.run([shell, '-NoProfile', '-NonInteractive', '-File',
                                 str(ROOT / 'tests/windows/check_driver_package_identity.ps1')],
                                capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=45)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('DRIVER_PACKAGE_IDENTITY_PASS', result.stdout)

if __name__ == '__main__':
    unittest.main()
