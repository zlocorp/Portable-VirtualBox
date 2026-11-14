"""Actual runner tail under nested PowerShell/GitHub exit semantics."""
from pathlib import Path
import os
import shutil
import subprocess
import unittest
ROOT=Path(__file__).resolve().parents[1]
SHELL=os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh') or shutil.which('powershell.exe')
@unittest.skipUnless(SHELL,'PowerShell required')
class AcquiredChildRunnerExit(unittest.TestCase):
    def run_case(self, scenario):
        return subprocess.run([SHELL,'-NoProfile','-NonInteractive','-File',
            str(ROOT/'tests/windows/check_acquired_child_runner_contract.ps1'),'-Scenario',scenario],
            capture_output=True,text=True,timeout=30)
    def test_validated_expected_failures_do_not_fail_github_wrapper(self):
        run=self.run_case('pass')
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('ACQUIRED_CHILD_CASES_PASS cases=3 expected_failures=2',run.stdout)
        self.assertIn('RUNNER_NESTED_RETURNED',run.stdout)
    def test_bad_status_or_marker_still_rejected(self):
        for scenario in ('normal-status','normal-marker','before-status','before-marker','after-status','after-marker'):
            with self.subTest(scenario=scenario):
                run=self.run_case(scenario)
                self.assertEqual(run.returncode,91,run.stdout+run.stderr)
                self.assertIn('RUNNER_CONTRACT_REJECTED scenario='+scenario,run.stdout)
                self.assertNotIn('RUNNER_NESTED_RETURNED',run.stdout)
