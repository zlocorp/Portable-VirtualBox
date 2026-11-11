"""Execute the actual private cleanup sequencing, without Windows/system effects."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest
ROOT=Path(__file__).resolve().parents[1]
SHELL=os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh') or shutil.which('powershell.exe')
class CleanupCompletion(unittest.TestCase):
    def test_main_and_build_use_private_sequence(self):
        source=ROOT/'source/privilege/SessionHelper.CleanupCompletion.cs'
        self.assertTrue(source.exists(), 'Missing checkpoint-before-diagnostics sequencing')
        self.assertIn('static void CompleteCleanupWorker(',source.read_text())
        self.assertNotIn('public static void CompleteCleanupWorker',source.read_text())
        main=(ROOT/'source/privilege/SessionHelper.Main.cs').read_text()
        self.assertIn('CompleteCleanupWorker(',main)
        prepare=main[main.index('                    if(prepare) {',main.index('bool withinDeadline=')):main.index('                        CompleteCleanupWorker(')]
        self.assertNotIn('CreatePayloadCheckpoint',prepare)
        self.assertNotIn('PayloadBreak',prepare)
        self.assertIn('stdout.GetAwaiter().GetResult()',prepare)
        self.assertIn('stderr.GetAwaiter().GetResult()',prepare)
        for point in ('BeforeStdout','BeforeStderr','BeforeFacts'):
            self.assertIn('PayloadBreak("'+point+'")',main)
            self.assertIn(point,(ROOT/'tests/windows/check_payload_cleanup_recovery.ps1').read_text())
        fixture=(ROOT/'tests/windows/check_payload_cleanup_recovery.ps1').read_text()
        self.assertIn("@{point='BeforeFacts';resume='Recover';initial='Recover'}",fixture)
        self.assertIn("$label+='-InitialRecover'",fixture)
        self.assertIn("('resume-same-recovery-'+$label)",fixture)
        self.assertLess(main.index('CompleteCleanupWorker('),main.rindex('ContinuePayloadRemoval('))
        self.assertIn('SessionHelper.CleanupCompletion.cs',(ROOT/'scripts/build_session_helper.ps1').read_text())
    @unittest.skipUnless(SHELL,'PowerShell compiler required')
    def test_actual_private_sequence(self):
        self.assertTrue((ROOT/'source/privilege/SessionHelper.CleanupCompletion.cs').exists(), 'Missing production sequence')
        run=subprocess.run([SHELL,'-NoProfile','-NonInteractive','-File',str(ROOT/'tests/windows/check_cleanup_completion.ps1')],capture_output=True,text=True,timeout=60)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('CLEANUP_COMPLETION_PASS',run.stdout)
