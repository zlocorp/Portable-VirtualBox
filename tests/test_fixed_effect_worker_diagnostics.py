"""Check diagnostic milestones without changing the runner's exit semantics."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHELL = os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh')
SCRIPT = ROOT / 'tests/windows/check_fixed_effect_worker_managed.ps1'


@unittest.skipUnless(SHELL, 'PowerShell required for managed diagnostics')
class FixedEffectWorkerDiagnostics(unittest.TestCase):
    def run_fixture(self, prior, environment_exit=None):
        # Model the Actions runner's normal wrapper; no native process is
        # launched by the managed fixture. Keep its pre-existing status intact.
        setup = ("Remove-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue"
                 if prior is None else '$global:LASTEXITCODE=5')
        if environment_exit is not None:
            setup += "; [Environment]::ExitCode=" + str(environment_exit)
        script = str(SCRIPT).replace("'", "''")
        command = (setup + "; & '" + script + "'; "
                   "if ((Test-Path -LiteralPath variable:\\LASTEXITCODE)) { exit $LASTEXITCODE }")
        return subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-Command', command],
                              cwd=ROOT, capture_output=True, text=True, timeout=120)

    def assert_milestones(self, output, last, environment_exit=0):
        status = lambda phase: (f'MANAGED_EXIT_STATUS phase={phase} last_exit={last} '
                                f'environment_exit={environment_exit}')
        events = [
            status('before'),
            'FIXED_EFFECT_MANAGED_PASS assertions=121',
            'FIXED_EFFECT_MANAGED_RETURNED result=0',
            status('after_fixed'),
            'SDS_DIAGNOSTIC_FILES_PASS',
            'SDS_DIAGNOSTIC_FILES_CLEANUP_ENTERED',
            'SDS_DIAGNOSTIC_FILES_CLEANUP_COMPLETED',
            'SDS_DIAGNOSTIC_FILES_RETURNED result=0',
            status('after_sds'),
            status('final'),
        ]
        positions = []
        for event in events:
            self.assertEqual(output.count(event), 1, f'{event} missing or duplicated: {output}')
            positions.append(output.index(event))
        self.assertEqual(positions, sorted(positions), output)
        statuses = re.findall(r'(?m)^MANAGED_EXIT_STATUS phase=(before|after_fixed|after_sds|final) '
                              r'last_exit=(absent|other|-?\d+) environment_exit=(-?\d+)\s*$', output)
        self.assertTrue(statuses, f'bounded exit status missing: {output}')
        self.assertEqual([phase for phase, _, _ in statuses],
                         ['before', 'after_fixed', 'after_sds', 'final'], output)
        self.assertTrue(all(value == last and int(env) == environment_exit for _, value, env in statuses), output)
        for _, value, env in statuses:
            if value not in ('absent', 'other'):
                self.assertLessEqual(-(2**31), int(value))
                self.assertLessEqual(int(value), 2**31 - 1)
            self.assertLessEqual(-(2**31), int(env))
            self.assertLessEqual(int(env), 2**31 - 1)

    def test_absent_last_exit_is_preserved(self):
        result = self.run_fixture(None)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_milestones(result.stdout, 'absent')

    def test_existing_nonzero_last_exit_is_preserved(self):
        result = self.run_fixture(5)
        self.assertEqual(result.returncode, 5, result.stdout + result.stderr)
        self.assert_milestones(result.stdout, '5')


    def test_environment_exit_code_is_preserved(self):
        baseline = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-Command',
                                   "Remove-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue; "
                                   "[Environment]::ExitCode=7; "
                                   "if ((Test-Path -LiteralPath variable:\\LASTEXITCODE)) { exit $LASTEXITCODE }"],
                                  cwd=ROOT, capture_output=True, text=True, timeout=120)
        result = self.run_fixture(None, environment_exit=7)
        self.assertEqual(result.returncode, baseline.returncode, result.stdout + result.stderr)
        self.assert_milestones(result.stdout, 'absent', environment_exit=7)

    def test_nonzero_sds_return_is_not_hidden(self):
        original = SCRIPT.read_text(encoding='utf-8')
        call = '[PortableVBox.SdsDiagnosticFilesTests]::Main()'
        self.assertEqual(original.count(call), 1, 'expected one real SDS call')
        windows = str(SCRIPT.parent).replace("'", "''")
        altered = original.replace('$PSScriptRoot', "'" + windows + "'")
        altered = altered.replace(call, '(& { return 5 })')
        with tempfile.TemporaryDirectory(prefix='pvbox-managed-nonzero-test-') as directory:
            copy = Path(directory) / 'fixture.ps1'
            copy.write_text(altered, encoding='utf-8')
            quoted = str(copy).replace("'", "''")
            env = os.environ.copy()
            env.update({'TMPDIR': directory, 'TMP': directory, 'TEMP': directory})
            result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-Command',
                                     "$ErrorActionPreference='Stop'; & '" + quoted + "'"],
                                    cwd=directory, env=env, capture_output=True, text=True, timeout=120)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('SDS_DIAGNOSTIC_FILES_RETURNED result=5', result.stdout)
        self.assertIn('SDS diagnostic file assertions failed', result.stdout + result.stderr)

    def test_injected_main_exception_is_not_hidden(self):
        original = SCRIPT.read_text(encoding='utf-8')
        call = '[PortableVBox.SdsDiagnosticFilesTests]::Main()'
        self.assertEqual(original.count(call), 1, 'expected one real SDS call')
        # The copy stays in a temporary directory; substitute only its source
        # location and the managed call that must fail. No production edits.
        window_dir = str(SCRIPT.parent).replace("'", "''")
        altered = original.replace('$PSScriptRoot', "'" + window_dir + "'")
        altered = altered.replace(call, "(& { throw 'INJECTED_SDS_TEST_EXCEPTION' })")
        with tempfile.TemporaryDirectory(prefix='pvbox-managed-diagnostic-test-') as directory:
            copy = Path(directory) / 'fixture.ps1'
            copy.write_text(altered, encoding='utf-8')
            quoted = str(copy).replace("'", "''")
            command = ("$ErrorActionPreference='Stop'; & '" + quoted + "'; "
                       "if ((Test-Path -LiteralPath variable:\\LASTEXITCODE)) { exit $LASTEXITCODE }")
            result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-Command', command],
                                    cwd=ROOT, capture_output=True, text=True, timeout=120)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('INJECTED_SDS_TEST_EXCEPTION', result.stdout + result.stderr)
        self.assertIn('FIXED_EFFECT_MANAGED_RETURNED result=0', result.stdout)
        self.assertNotIn('SDS_DIAGNOSTIC_FILES_RETURNED', result.stdout)

    def test_controlled_finalization_does_not_throw(self):
        # All managed assertions run, including the injected Dispose(true)
        # exception; then exercise cleanup of its test objects in this child.
        script = str(SCRIPT).replace("'", "''")
        command = ("$ErrorActionPreference='Stop'; & '" + script + "'; "
                   "[GC]::Collect(); [GC]::WaitForPendingFinalizers(); "
                   "if ([PortableVBox.SdsDiagnosticFilesTests]::CloseFaultFinalizerDisposals -lt 1) { throw 'CLOSE_FAULT_FINALIZER_NOT_OBSERVED' }; "
                   "Write-Host 'CONTROLLED_FINALIZERS_COMPLETED'; "
                   "if ((Test-Path -LiteralPath variable:\\LASTEXITCODE)) { exit $LASTEXITCODE }")
        with tempfile.TemporaryDirectory(prefix='pvbox-finalizer-test-') as directory:
            env = os.environ.copy()
            env.update({'TMPDIR': directory, 'TMP': directory, 'TEMP': directory})
            result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-Command', command],
                                    cwd=directory, env=env, capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('SDS_DIAGNOSTIC_FILES_RETURNED result=0', result.stdout)
        self.assertIn('CONTROLLED_FINALIZERS_COMPLETED', result.stdout)

    def test_injected_cleanup_exception_remains_visible(self):
        wrapper = SCRIPT.read_text(encoding='utf-8')
        cs_path = SCRIPT.parent / 'SdsDiagnosticFilesTests.cs'
        source = cs_path.read_text(encoding='utf-8')
        cleanup = 'Directory.Delete(root,true)'
        self.assertEqual(source.count(cleanup), 1, 'expected one real SDS cleanup')
        source = source.replace(cleanup, cleanup + '; if (DateTime.UtcNow.Ticks >= 0) throw new IOException("INJECTED_CLEANUP_EXCEPTION")')
        with tempfile.TemporaryDirectory(prefix='pvbox-managed-cleanup-test-') as directory:
            copy_cs = Path(directory) / 'SdsDiagnosticFilesTests.cs'
            copy_cs.write_text(source, encoding='utf-8')
            location = "(Join-Path $PSScriptRoot 'SdsDiagnosticFilesTests.cs')"
            self.assertEqual(wrapper.count(location), 1, 'expected one managed fixture source')
            wrapper = wrapper.replace(location, "'" + str(copy_cs).replace("'", "''") + "'")
            wrapper = wrapper.replace('$PSScriptRoot', "'" + str(SCRIPT.parent).replace("'", "''") + "'")
            copy_ps = Path(directory) / 'fixture.ps1'
            copy_ps.write_text(wrapper, encoding='utf-8')
            quoted = str(copy_ps).replace("'", "''")
            env = os.environ.copy()
            env.update({'TMPDIR': directory, 'TMP': directory, 'TEMP': directory})
            result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-Command',
                                     "$ErrorActionPreference='Stop'; & '" + quoted + "'"],
                                    cwd=directory, env=env, capture_output=True, text=True, timeout=120)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('INJECTED_CLEANUP_EXCEPTION', result.stdout + result.stderr)
        self.assertIn('SDS_DIAGNOSTIC_FILES_CLEANUP_ENTERED', result.stdout)
        self.assertNotIn('SDS_DIAGNOSTIC_FILES_CLEANUP_COMPLETED', result.stdout)
        self.assertNotIn('SDS_DIAGNOSTIC_FILES_RETURNED', result.stdout)


if __name__ == '__main__':
    unittest.main()
