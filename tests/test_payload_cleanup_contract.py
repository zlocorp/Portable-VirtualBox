"""Integration gates for fixed, owner-bound private-payload continuation."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class PayloadCleanupContracts(unittest.TestCase):
    def source(self,name):
        path=ROOT/name
        self.assertTrue(path.exists(), 'Missing payload continuation implementation: '+name)
        return path.read_text(encoding='utf-8-sig')
    def test_payload_continuation_precedes_full_staging_and_never_reenters_worker(self):
        text=self.source('source/privilege/SessionHelper.Main.cs')
        self.assertIn('ContinuePayloadRemoval',text)
        branch=text.index('ContinuePayloadRemoval')
        self.assertLess(branch,text.index('CreateProtectedDirectory(app'))
        self.assertLess(branch,text.index('InstallScripts(session,prepare)'))
        self.assertIn('return 0;',text[branch:text.index('CreateProtectedDirectory(app')])
    def test_native_objects_and_existing_parent_locks_bind_deletion(self):
        text=self.source('source/privilege/SessionHelper.PayloadCleanup.cs')+self.source('source/privilege/SessionHelper.PayloadObjects.cs')
        for check in ('GetFileInformationByHandleEx','GetSecurityInfo','SetFileInformationByHandle','PayloadCleanupJournal','PayloadCleanupPlan','AssertNoVBoxResources','VerifyPayloadOwner','CreatePayloadCheckpoint'):
            self.assertIn(check,text)
        self.assertNotIn('File.Delete(',text)
        self.assertNotIn('Directory.Delete(',text)
        self.assertNotIn('Process.Start(',text)
        self.assertNotIn('File.Exists(',text)
        self.assertNotIn('Directory.Exists(',text)
        self.assertIn('ReleasePayloadLocks',self.source('source/privilege/SessionHelper.cs'))
        self.assertIn('CreateFileW(path,0x81,3',self.source('source/privilege/SessionHelper.cs'))
        self.assertIn('CreateFileW(path,0x20081,3',text)
    def test_build_compiles_fixed_modules_and_native_contracts_execute(self):
        build=self.source('scripts/build_session_helper.ps1')
        for name in ('PayloadCleanupJournal.cs','PayloadCleanupPlan.cs','SessionHelper.PayloadCleanup.cs','System.ServiceProcess.dll'):
            self.assertIn(name,build)
        workflow=self.source('.github/workflows/native-tests.yml')
        self.assertIn('check_payload_cleanup_contracts.ps1',workflow)
    def test_controlled_host_fixture_is_not_workstation_acceptance(self):
        text=self.source('tests/windows/check_payload_cleanup_recovery.ps1')
        for fragment in ('github-hosted','AfterFirstDelete','BeforeMarker','PVBOX_TEST_PAYLOAD_BREAK_AT','payload-cleanup.journal','interactive_uac_verified=$false'):
            self.assertIn(fragment,text)
        self.assertNotIn('Stop-Process',text)
        self.assertNotIn('sc.exe delete',text)
if __name__=='__main__': unittest.main()
