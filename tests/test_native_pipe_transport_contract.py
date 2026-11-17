"""Behavioral managed protocol checks; never substitute for native Windows I/O."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / 'tests/windows/check_native_pipe_transport.ps1'
SHELL = os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh') or shutil.which('powershell.exe')


def strict_json(line):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('Duplicate key')
            result[key] = value
        return result
    def invalid(value):
        raise ValueError('Non-JSON constant: ' + value)
    return json.loads(line, object_pairs_hook=pairs, parse_constant=invalid)


def validate_evidence(path):
    path = Path(path)
    if not 0 < path.stat().st_size <= 262144:
        raise ValueError('Evidence size bound')
    reports, total = [], 0
    kinds = {'managed_pipe_contracts', 'native_pipe_case', 'native_pipe_failure', 'native_pipe_summary'}
    with path.open('rb') as stream:
        while True:
            # The bound is enforced before reading/decoding an entire hostile line.
            line = stream.readline(4097)
            if not line:
                break
            total += len(line)
            if len(line) > 4096 or total > 262144 or len(reports) >= 64 or not line.endswith(b'\n'):
                raise ValueError('Evidence record bound or torn line')
            report = strict_json(line.decode('utf-8', errors='strict'))
            if not isinstance(report, dict) or report.get('mutation_authorized') is not False:
                raise ValueError('Evidence never authorizes mutation')
            if report.get('kind') not in kinds or report.get('status') not in {'PASS', 'FAIL'}:
                raise ValueError('Unknown evidence record')
            reports.append(report)
    if not reports:
        raise ValueError('Empty evidence')
    return reports


class NativePipeTransportContract(unittest.TestCase):
    def test_bounded_strict_failure_evidence(self):
        failure = {'kind': 'native_pipe_summary', 'status': 'FAIL', 'cases': 0,
                   'checks': 1, 'all_owners_released': False, 'mutation_authorized': False}
        with tempfile.TemporaryDirectory(prefix='pvbox-pipe-json-') as root:
            path = Path(root) / 'failure.jsonl'
            path.write_bytes((json.dumps(failure) + '\n').encode('utf-8'))
            self.assertEqual(validate_evidence(path), [failure])
            malformed = [
                b'{"kind":"native_pipe_summary","mutation_authorized":true}\n',
                b'{"mutation_authorized":false,"mutation_authorized":false}\n',
                b'{"mutation_authorized":false,"value":NaN}\n',
                b'{"mutation_authorized":false,"value":"\xff"}\n',
                (b' ' * 4096) + b'{}\n',
                b'{}\n' * 90000,
                b'[]\n', b'',
            ]
            for data in malformed:
                path.write_bytes(data)
                with self.subTest(size=len(data)), self.assertRaises((ValueError, UnicodeError)):
                    validate_evidence(path)

    @unittest.skipUnless(SHELL, 'PowerShell compiler required')
    def test_managed_pipe_behavior(self):
        result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-File', str(RUNNER), '-ManagedOnly'],
                                text=True, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        reports = [strict_json(line) for line in result.stdout.splitlines() if line.startswith('{')]
        self.assertEqual(len(reports), 1, result.stdout)
        report = reports[0]
        self.assertEqual(report['kind'], 'managed_pipe_contracts')
        self.assertEqual(report['status'], 'PASS')
        self.assertGreaterEqual(report['checks'], 85)
        self.assertEqual(report['native_calls'], 0)
        self.assertIs(report['mutation_authorized'], False)

    @unittest.skipUnless(SHELL, 'PowerShell required')
    def test_linux_skip_is_explicit(self):
        if os.name == 'nt':
            self.skipTest('Native evidence belongs to the Windows runner')
        result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-File', str(RUNNER)],
                                text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('SKIP native pipe transport: Windows required', result.stdout)
        self.assertNotIn('native_pipe_case', result.stdout)

    @unittest.skipUnless(SHELL, 'PowerShell required')
    def test_serialized_evidence_cannot_resume(self):
        result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-File', str(RUNNER),
                                 '-ManagedOnly', '-ResumeEvidence', '{"mutation_authorized":true}'],
                                text=True, capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('"status":"PASS"', result.stdout)


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--validate-evidence':
        reports = validate_evidence(sys.argv[2])
        print('PASS strict bounded UTF-8 JSONL: %d observational records' % len(reports))
    else:
        unittest.main()
