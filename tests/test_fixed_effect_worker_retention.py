"""Childless Windows WAIT_FAILED probe wiring and net48 build, not native proof."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which('pwsh')
PROBE = ROOT/'tests/windows/FixedEffectWorkerRetentionProbe.cs'
RUNNER = ROOT/'tests/windows/check_fixed_effect_worker_retention.ps1'

class FixedEffectWorkerRetention(unittest.TestCase):
    def test_childless_probe_is_closed_and_keeps_actual_owner(self):
        self.assertTrue(PROBE.exists(), 'Missing actual owner WAIT_FAILED retention probe')
        text = PROBE.read_text()
        for expected in ('WaitForSingleObject(IntPtr.Zero,0)', 'Marshal.GetLastWin32Error()',
                         'ObserveAndWait', 'MethodInfo', 'ManualResetEvent', 'Mutex',
                         'thread.Interrupt()', 'Environment.Exit', 'FIXED_EFFECT_RETENTION_PASS'):
            self.assertIn(expected, text)
        for forbidden in ('CreateProcess', 'Process.Start', 'FixedEffectWorker.Run(',
                          'TerminateProcess', 'Thread.Abort', 'Process.Kill', 'new IntPtr(-1)'):
            self.assertNotIn(forbidden, text)
        self.assertIn('public static int Main()', text)
        runner = RUNNER.read_text()
        self.assertIn('source/privilege/FixedEffectWorker.cs', runner)
        self.assertIn('Compile-FixedFixtureSources', runner)
        self.assertIn("$env:RUNNER_ENVIRONMENT -ne 'github-hosted'", runner)
        self.assertNotIn('Replace(', runner)
        workflow = (ROOT/'.github/workflows/native-tests.yml').read_text()
        self.assertIn('./tests/windows/check_fixed_effect_worker_retention.ps1', workflow)

    @unittest.skipUnless(PWSH and os.environ.get('PVBOX_TEST_NET48_REFERENCES'), 'net48 compiler references unavailable')
    def test_retention_probe_compiles_against_net48(self):
        with tempfile.TemporaryDirectory() as temp:
            output = str(Path(temp)/'retention.exe').replace("'", "''")
            command = (". ./tests/windows/NativeFixedFixtureBuild.ps1; "
                "Compile-FixedFixtureSources @((Resolve-Path source/privilege/FixedEffectWorker.cs).Path,"
                "(Resolve-Path tests/windows/FixedEffectWorkerRetentionProbe.cs).Path) '" + output +
                "' 'PortableVBox.FixedEffectWorkerRetentionProbe'")
            run = subprocess.run([PWSH, '-NoProfile', '-Command', command], cwd=ROOT,
                                 capture_output=True, text=True, timeout=60)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
