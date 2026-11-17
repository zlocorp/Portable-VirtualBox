"""Real-child restricted-handle fixture build/wiring; Windows supplies native proof."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which('pwsh')
PROBE = ROOT/'tests/windows/FixedEffectAcquiredChildProbe.cs'

class FixedEffectAcquiredChild(unittest.TestCase):
    def test_closed_real_child_and_immutable_owner(self):
        self.assertTrue(PROBE.exists(), 'Missing acquired-child restricted-handle probe')
        text = PROBE.read_text()
        for token in ('CreateProcessW(', 'DuplicateHandle(', '0x1000', 'ObserveAndWait',
                      'NaturalExit', 'WAIT_FAILED', 'acquired_child=true', 'synthetic_adoption=true',
                      'Thread.Interrupt', 'Environment.Exit'):
            self.assertIn(token, text)
        for token in ('TerminateProcess', 'Process.Kill', 'Thread.Abort', 'DUPLICATE_CLOSE_SOURCE',
                      'FixedEffectWorker.Run(', 'Process.Start(', 'OpenProcess('):
            self.assertNotIn(token, text)
        runner=(ROOT/'tests/windows/check_fixed_effect_acquired_child.ps1').read_text()
        self.assertIn('source/privilege/FixedEffectWorker.cs',runner)
        self.assertIn('Compile-FixedFixtureSources',runner)
        self.assertNotIn('.Replace(',runner)
        self.assertIn('check_fixed_effect_acquired_child.ps1',(ROOT/'.github/workflows/native-tests.yml').read_text())
        for mode in ('--fail-before-adoption','--fail-after-retention'):
            self.assertIn(mode,text)
            self.assertIn(mode,runner)
        self.assertIn('ACQUIRED_CHILD_EXPECTED_FAILURE',runner)
        self.assertIn('try {release.Set();}catch { }',text)
        self.assertIn('catch {Unknown("natural_exit_wait_unavailable");}',text)
        self.assertIn('no_exit_claim=true");Console.Error.Flush();}catch { }',text)

    @unittest.skipUnless(PWSH and os.environ.get('PVBOX_TEST_NET48_REFERENCES'), 'net48 compiler references unavailable')
    def test_compile_real_child_probe_net48(self):
        self.assertTrue(PROBE.exists(), 'Missing acquired-child restricted-handle probe')
        with tempfile.TemporaryDirectory() as tmp:
            output=str(Path(tmp)/'acquired.exe').replace("'","''")
            command=(". ./tests/windows/NativeFixedFixtureBuild.ps1; Compile-FixedFixtureSources "
                     "@((Resolve-Path source/privilege/FixedEffectWorker.cs).Path,"
                     "(Resolve-Path tests/windows/FixedEffectAcquiredChildProbe.cs).Path) '"+
                     output+"' 'PortableVBox.FixedEffectAcquiredChildProbe'")
            run=subprocess.run([PWSH,'-NoProfile','-Command',command],cwd=ROOT,capture_output=True,text=True,timeout=60)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
