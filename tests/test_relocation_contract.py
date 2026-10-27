"""Bounded contract for the disposable relocation experiment."""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'scripts'/'vbox_root_relocation_probe.ps1'
WORKFLOW=ROOT/'.github'/'workflows'/'portable-relocation.yml'

class PortableRelocationContract(unittest.TestCase):
    def test_ephemeral_only_and_exact_service_lifecycle(self):
        s=SCRIPT.read_text(encoding='utf-8')
        for expected in (
            'RUNNER_ENVIRONMENT', 'github-hosted', 'GITHUB_ACTIONS',
            'GITHUB_REPOSITORY', 'RUNNER_TEMP', 'VBOX_USER_HOME',
            'VBoxManage.exe', 'VBoxSDS.exe', '--unregservice',
            'Get-AuthenticodeSignature', 'Get-FileHash', 'WaitForExit',
            'image_path', 'service_cleanup', 'Move-Item',
        ):
            self.assertIn(expected,s)

    def test_preserve_existing_vm_and_disk(self):
        s=SCRIPT.read_text(encoding='utf-8')
        for expected in (
            'unregistervm', 'registervm', 'createvm', 'createmedium',
            'storageattach', 'showvminfo', 'list', 'vms',
            'original_uuid', 'relocated_uuid', 'same_uuid',
            'original_disk_sha256', 'relocated_disk_sha256',
            'machinefolder', 'profile_moved', 'relocation-results.json',
            'old_snapshot_take', 'old_snapshot_list', 'new_snapshot_list',
            'same_snapshot_uuid', 'snapshot_bytes_preserved',
            'snapshot_path_relocated', 'original_snapshot_sha256',
        ):
            self.assertIn(expected,s)
        active='\n'.join(l for l in s.splitlines() if not l.lstrip().startswith('#'))
        for pattern in (
            r'(?i)\b(?:taskkill|Stop-Process|Remove-Service|msiexec)\b',
            r'(?i)\bunregistervm[^\r\n]*--delete',
            r'(?i)\b(?:Remove-Item|Clear-Content)\b',
            r'(?i)\b(?:Start-Process)[^\r\n]*VirtualBoxVM',
        ):
            self.assertNotRegex(active,pattern)

    def test_snapshot_chain_never_uses_xml_text_substitution_or_removal(self):
        script=SCRIPT.read_text(encoding='utf-8')
        for marker in ("'Snapshots'", "snapshot',$vm,'take'", "'new_snapshot_list'",
                       'snapshotChainRestored', 'originalSnapshotUuid',
                       'Get-FileHash -LiteralPath $relocatedSnapshotPath'):
            self.assertIn(marker, script)
        active='\n'.join(line for line in script.splitlines()
                         if not line.lstrip().startswith('#'))
        for forbidden in ('--delete', 'Kill()', 'taskkill', 'Remove-Item'):
            self.assertNotIn(forbidden, active)
        self.assertIn("$p.WaitForExit()",script)
        self.assertIn("hddListing.Replace('/', '\\')", script)
        self.assertIn('normalizedHdds -match [regex]::Escape($relocatedSnapshotPath)',script)
        self.assertIn('SnapshotUUID=',script)

    def test_drive_letter_alias_reassignment_is_explicit_and_disposable(self):
        s=SCRIPT.read_text(encoding='utf-8')
        for expected in ('VhdDriveLetterChange','vbox_vhd_volume.ps1','P:','Q:',
                         'drive_letters_changed','visible_old_root','visible_new_root'):
            self.assertIn(expected,s)
        workflow=WORKFLOW.read_text(encoding='utf-8')
        self.assertIn('relocation_mode',workflow)
        self.assertIn('vhd-letter',workflow)

    def test_workflow_only_artifacts_metadata(self):
        text=WORKFLOW.read_text(encoding='utf-8')
        self.assertIn('windows-2022',text)
        self.assertIn('contents: read',text)
        self.assertIn('vbox_root_relocation_probe.ps1',text)
        self.assertIn('relocation-results.json',text)
        self.assertIn('retention-days: 7',text)
        self.assertNotRegex(text,r'(?i)actions/upload-artifact[^\n]*\n[^\n]*\n[^\n]*\bapp64\b')

if __name__=='__main__':
    unittest.main()
