"""Run the test-only observation protocol; Linux never claims native evidence."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHELL = os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh') or shutil.which('powershell.exe')
RUNNER = ROOT / 'tests/windows/check_native_launch_observation.ps1'


class NativeLaunchObservationContract(unittest.TestCase):
    def test_observation_runner_exists(self):
        self.assertTrue(RUNNER.is_file(), 'Missing safe native observation runner')

    @unittest.skipUnless(SHELL, 'PowerShell compiler required')
    def test_managed_observation_contracts(self):
        self.assertTrue(RUNNER.is_file(), 'Missing safe native observation runner')
        result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-File', str(RUNNER), '-ManagedOnly'],
                                text=True, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        summary = next((json.loads(line) for line in result.stdout.splitlines()
                        if line.startswith('{') and 'managed_contracts' in line), None)
        self.assertIsNotNone(summary, result.stdout)
        self.assertFalse(summary['mutation_authorized'])
        self.assertGreaterEqual(summary['checks'], 25)
        self.assertEqual(summary['native_calls'], 0)
        self.assertEqual(summary['status'], 'PASS')
        inspections = [json.loads(line) for line in result.stdout.splitlines()
                       if line.startswith('{') and 'method_inspection' in line]
        self.assertEqual(len(inspections), 3, 'Actual, unavailable metadata, and unavailable hash reports must be strict JSON')
        for report in inspections:
            self.assertFalse(report['mutation_authorized'])
            self.assertLessEqual(len(json.dumps(report).encode()), 262144)
        for report in inspections[1:]:
            self.assertEqual(report['assembly_file_status'], 'unsupported')
            self.assertEqual(report['inspection_status'], 'unsupported')

    @unittest.skipUnless(SHELL, 'PowerShell required')
    def test_persisted_evidence_is_not_an_input_or_resume_authority(self):
        with tempfile.TemporaryDirectory(prefix='pvbox-untrusted-observation-') as root:
            for label, data in [('historical', '{"axis":"EXACT_CHILD_EXITED","exit_code":0}'),
                                ('foreign', '{"parent_pid":123,"mutation_authorized":true}'),
                                ('torn', '{"axis":"EXACT_CHILD_'), ('omitted', '')]:
                path = Path(root) / (label + '.json')
                path.write_text(data)
                result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-File', str(RUNNER),
                                         '-ManagedOnly', '-ResumeEvidence', str(path)],
                                        text=True, capture_output=True, timeout=30)
                self.assertNotEqual(result.returncode, 0, label + ' evidence was accepted as input')
                self.assertNotIn('"status":"PASS"', result.stdout)
                self.assertNotIn('native_observation', result.stdout)

    @unittest.skipUnless(SHELL, 'PowerShell required')
    def test_non_windows_skip_is_explicit(self):
        if os.name == 'nt':
            self.skipTest('Windows native observations belong to the bounded native CI runner')
        self.assertTrue(RUNNER.is_file(), 'Missing safe native observation runner')
        result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-File', str(RUNNER)],
                                text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('SKIP native launch observations: Windows required', result.stdout)
        self.assertNotIn('native_contracts', result.stdout)


if __name__ == '__main__':
    unittest.main()
