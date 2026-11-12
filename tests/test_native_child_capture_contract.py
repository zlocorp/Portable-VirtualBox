"""Fixed-child evidence contracts; synthetic fixtures are never native evidence."""
import copy
import json
import math
import os
from pathlib import Path
import shutil
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / 'tests/windows/check_native_child_capture.ps1'
SHELL = os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh') or shutil.which('powershell.exe')
CASES = ('Empty', 'Binary', 'Large', 'Nonzero', 'Exit259', 'PostCreateFault',
         'CaptureFault', 'EvidenceFault', 'WithheldEof')
UNKNOWN_CASES = frozenset(('PostCreateFault', 'CaptureFault', 'EvidenceFault', 'WithheldEof'))
CASE_BOOLS = frozenset(('created', 'exit_observed', 'eof_stdout', 'eof_stderr',
                       'resources_released', 'retained_owner', 'sentinel_probe',
                       'sentinel_unsignaled', 'held_writer_blocked_eof',
                       'one_shot_refused', 'mutation_authorized'))
CASE_FIELDS = CASE_BOOLS | frozenset(('kind', 'case', 'status', 'overall', 'exit_code',
                                    'stdout_bytes', 'stderr_bytes', 'stdout_hash',
                                    'stderr_hash', 'rounds', 'fault_site', 'evidence_bytes_written',
                                    'create_calls', 'wait_calls', 'exit_code_reads', 'channels',
                                    'create_error', 'assertion_failed_at'))
CHANNEL_FIELDS = frozenset(('retained', 'discarded', 'read_issued', 'read_terminal',
                            'read_pending', 'read_immediate', 'read_visits', 'max_read_gap'))
SUMMARY_FIELDS = frozenset(('kind', 'status', 'cases', 'failed',
                            'all_owners_released', 'mutation_authorized'))


def strict_json(line):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('Duplicate JSON key')
            result[key] = value
        return result

    def invalid(value):
        raise ValueError('Nonfinite JSON number: ' + value)

    def finite(value):
        number = float(value)
        if not math.isfinite(number):
            invalid(value)
        return number

    try:
        return json.loads(line, object_pairs_hook=pairs, parse_constant=invalid, parse_float=finite)
    except RecursionError as error:
        raise ValueError('Evidence nesting bound') from error


def bounded_integer(record, field, maximum, minimum=0):
    value = record[field]
    if type(value) is not int or not minimum <= value <= maximum:
        raise ValueError('Invalid bounded integer: ' + field)


def validate_case(report):
    if set(report) != CASE_FIELDS:
        raise ValueError('Unexpected or missing native case fields')
    if type(report['case']) is not str or report['case'] not in CASES:
        raise ValueError('Unknown fixed case')
    if report['overall'] not in ('OBSERVED', 'UNKNOWN'):
        raise ValueError('Unknown observation state')
    for field in CASE_BOOLS:
        if type(report[field]) is not bool:
            raise ValueError('Invalid boolean: ' + field)
    for field, maximum in (('exit_code', 4294967295), ('stdout_bytes', 300000),
                           ('stderr_bytes', 300000), ('rounds', 32768), ('fault_site', 3),
                           ('evidence_bytes_written', 1), ('create_calls', 1),
                           ('wait_calls', 32768), ('exit_code_reads', 32768),
                           ('create_error', 4294967295)):
        bounded_integer(report, field, maximum)
    bounded_integer(report, 'assertion_failed_at', 64, minimum=-1)
    if type(report['channels']) is not list or len(report['channels']) != 2:
        raise ValueError('Exactly two observed channels required')
    for channel in report['channels']:
        if type(channel) is not dict or set(channel) != CHANNEL_FIELDS:
            raise ValueError('Unexpected or missing channel fields')
        for field in CHANNEL_FIELDS:
            maximum = {'retained': 65536, 'discarded': 300000, 'max_read_gap': 1}.get(field, 32768)
            bounded_integer(channel, field, maximum)
    for field in ('stdout_hash', 'stderr_hash'):
        if type(report[field]) is not str or re.fullmatch('[0-9a-f]{16}', report[field]) is None:
            raise ValueError('Invalid byte hash: ' + field)
    if report['resources_released'] and report['retained_owner']:
        raise ValueError('Contradictory release observations')
    if report['status'] == 'PASS':
        expected = 'UNKNOWN' if report['case'] in UNKNOWN_CASES else 'OBSERVED'
        if report['overall'] != expected:
            raise ValueError('Unexpected case observation state')
        required = ('created', 'exit_observed', 'eof_stdout', 'eof_stderr',
                    'resources_released', 'sentinel_probe', 'sentinel_unsignaled', 'one_shot_refused')
        if not all(report[field] for field in required) or report['retained_owner'] or report['rounds'] == 0:
            raise ValueError('PASS case lacks required independent observations')
        if report['held_writer_blocked_eof'] != (report['case'] == 'WithheldEof'):
            raise ValueError('Withheld EOF observation mismatch')
        expected_fault = {'PostCreateFault': 1, 'CaptureFault': 2, 'EvidenceFault': 3}.get(report['case'], 0)
        if report['fault_site'] != expected_fault:
            raise ValueError('Expected fault site was not observed')
        if report['evidence_bytes_written'] != (1 if report['case'] == 'EvidenceFault' else 0):
            raise ValueError('Evidence fault write observation mismatch')
        if report['create_calls'] != 1 or report['wait_calls'] < 1 or report['exit_code_reads'] < 1:
            raise ValueError('PASS requires actual native lifecycle calls')
        if report['create_error'] != 0 or report['assertion_failed_at'] != 0:
            raise ValueError('PASS contradicts a creation or assertion failure')
        for channel, total in zip(report['channels'], (report['stdout_bytes'], report['stderr_bytes'])):
            if channel['retained'] + channel['discarded'] != total:
                raise ValueError('Channel byte accounting mismatch')
            if channel['read_issued'] != channel['read_terminal'] or channel['read_visits'] != report['rounds']:
                raise ValueError('Channel completion or fair-visit observation mismatch')
        if report['case'] in ('CaptureFault', 'EvidenceFault') and report['channels'][0]['discarded'] == 0:
            raise ValueError('Capture fault requires observed continued discard')


def validate_summary(report):
    if set(report) != SUMMARY_FIELDS:
        raise ValueError('Unexpected or missing summary fields')
    bounded_integer(report, 'cases', 9)
    bounded_integer(report, 'failed', 9)
    if type(report['all_owners_released']) is not bool:
        raise ValueError('Invalid summary release boolean')


def validate_evidence(path, require_pass=False):
    """Validate diagnostics only. Returned dictionaries never authorize resource release."""
    path = Path(path)
    if not 0 < path.stat().st_size <= 262144:
        raise ValueError('Evidence artifact size bound')
    reports, total, seen = [], 0, set()
    summary = None
    with path.open('rb') as stream:
        while True:
            # Bound before UTF-8 decoding/JSON parsing, including a file growing after stat.
            line = stream.readline(4097)
            if not line:
                break
            total += len(line)
            if len(line) > 4096 or total > 262144 or len(reports) >= 10 or not line.endswith(b'\n'):
                raise ValueError('Evidence record bound or torn line')
            report = strict_json(line.decode('utf-8', errors='strict'))
            if type(report) is not dict or report.get('mutation_authorized') is not False:
                raise ValueError('Evidence cannot authorize mutation')
            if report.get('status') not in ('PASS', 'FAIL') or summary is not None:
                raise ValueError('Unknown status or record after final summary')
            if report.get('kind') == 'native_child_case':
                validate_case(report)
                if report['case'] in seen:
                    raise ValueError('Duplicate fixed case')
                seen.add(report['case'])
            elif report.get('kind') == 'native_child_summary':
                validate_summary(report)
                summary = report
            else:
                raise ValueError('Unknown native child record')
            reports.append(report)
    if summary is None or summary['cases'] != len(seen):
        raise ValueError('Missing summary or mismatched case count')
    cases = reports[:-1]
    failed = sum(report['status'] == 'FAIL' for report in cases)
    if summary['failed'] < failed:
        raise ValueError('Summary hides failed cases')
    if summary['all_owners_released'] and any(not report['resources_released'] for report in cases):
        raise ValueError('Summary contradicts retained native owners')
    if summary['status'] == 'PASS':
        if seen != set(CASES) or summary['failed'] != 0 or not summary['all_owners_released']:
            raise ValueError('PASS requires all nine successful observations')
    elif summary['failed'] == 0:
        raise ValueError('FAIL summary needs a failed check or case')
    if require_pass and summary['status'] != 'PASS':
        raise ValueError('Valid failure diagnostics are not a passing test run')
    return reports


def sample_records():
    """Schema fixtures only: byte totals/hashes are intentionally not OS evidence."""
    records = []
    for name in CASES:
        stdout_bytes = 0 if name == 'Empty' else (8192 if name in ('CaptureFault', 'EvidenceFault') else 8)
        retained = 0 if name == 'Empty' else (4096 if name in ('CaptureFault', 'EvidenceFault') else 8)
        records.append({
            'kind': 'native_child_case', 'case': name, 'status': 'PASS',
            'overall': 'UNKNOWN' if name in UNKNOWN_CASES else 'OBSERVED',
            'created': True, 'exit_observed': True,
            'exit_code': 259 if name == 'Exit259' else (23 if name == 'Nonzero' else 0),
            'eof_stdout': True, 'eof_stderr': True, 'resources_released': True,
            'retained_owner': False, 'stdout_bytes': stdout_bytes, 'stderr_bytes': 0,
            'stdout_hash': '0123456789abcdef', 'stderr_hash': 'cbf29ce484222325',
            'sentinel_probe': True, 'sentinel_unsignaled': True,
            'held_writer_blocked_eof': name == 'WithheldEof', 'one_shot_refused': True,
            'rounds': 1, 'mutation_authorized': False,
            'fault_site': {'PostCreateFault': 1, 'CaptureFault': 2, 'EvidenceFault': 3}.get(name, 0),
            'evidence_bytes_written': 1 if name == 'EvidenceFault' else 0,
            'create_calls': 1, 'wait_calls': 1, 'exit_code_reads': 1,
            'create_error': 0, 'assertion_failed_at': 0,
            'channels': [
                {'retained': retained, 'discarded': stdout_bytes - retained,
                 'read_issued': 1, 'read_terminal': 1, 'read_pending': 1,
                 'read_immediate': 0, 'read_visits': 1, 'max_read_gap': 0},
                {'retained': 0, 'discarded': 0, 'read_issued': 1, 'read_terminal': 1,
                 'read_pending': 1, 'read_immediate': 0, 'read_visits': 1, 'max_read_gap': 0},
            ],
        })
    records.append({'kind': 'native_child_summary', 'status': 'PASS', 'cases': 9,
                    'failed': 0, 'all_owners_released': True, 'mutation_authorized': False})
    return records


def expected_hash(length, seed=0, header=False):
    value = 14695981039346656037
    data = (bytes((80, 86, 67, 50, 1, 0, 0, 165)) if header else b'')
    data += bytes((offset * 31 + seed) & 255 for offset in range(length))
    for item in data:
        value = ((value ^ item) * 1099511628211) & ((1 << 64) - 1)
    return format(value, '016x')


class SentinelByteContract(unittest.TestCase):
    def test_independent_pvc2_hashes_keep_exact_body_sizes_and_stderr(self):
        for size, expected in ((17, 'e6a7f5deb30873c0'), (4097, '031381f5c4fbe740'),
                               (196731, 'c1f1accadf2339e9')):
            with self.subTest(size=size):
                self.assertEqual(expected_hash(size, header=True), expected)
        self.assertEqual(expected_hash(0), 'cbf29ce484222325')
        self.assertEqual(expected_hash(257, 71), 'c98455caf71ceb86')
        self.assertEqual(expected_hash(204829, 71), '8b07499bc23a9f3e')


class SentinelSourceWiringContract(unittest.TestCase):
    def test_all_three_child_builds_use_only_runtime_sentinel_dependencies(self):
        expected = {'NativeCaptureFixtureChild.cs', 'NativeLaunchEnvironmentObservation.cs',
                    'NativeSentinelObservation.cs', 'NativeSentinelObservationNative.cs'}
        helper = (ROOT / 'tests/windows/NativeFixedFixtureBuild.ps1').read_text()
        child = helper.split('$childNames=@(', 1)[1].split(')', 1)[0]
        names = re.findall(r"'([A-Za-z]+\.cs)'", child)
        self.assertEqual(set(names), expected)
        self.assertEqual(len(names), len(expected))
        for runner in ('check_native_child_capture.ps1', 'check_native_launch_environment.ps1',
                       'check_native_fixed_image_observation.ps1'):
            text = (ROOT / 'tests/windows' / runner).read_text(encoding='utf-8')
            with self.subTest(runner=runner):
                self.assertIn(". (Join-Path $PSScriptRoot 'NativeFixedFixtureBuild.ps1')", text)
                self.assertEqual(text.count('New-FixedFixtureBuild $out'), 1)
                self.assertNotIn('NativeCaptureFixtureChild.cs', text)
        workflow = (ROOT / '.github/workflows/native-tests.yml').read_text(encoding='utf-8')
        for name in ('NativeSentinelObservation.cs', 'NativeSentinelObservationNative.cs',
                     'NativeSentinelObservationNativeTests.cs'):
            self.assertIn('      - tests/windows/' + name, workflow)

    def test_child_main_roots_owner_before_observation_and_never_retries_cleanup(self):
        # A structural lifetime check supplements the real output/exception tests.
        text = (ROOT / 'tests/windows/NativeCaptureFixtureChild.cs').read_text(encoding='utf-8')
        main = text.split('  static int Main(string[] args) {', 1)[1]
        self.assertLess(main.index('observerRoot=new SentinelObserver(arguments);'),
                        main.index('observerRoot.ObserveOnce(new NativeSentinelQueryApi())'))
        self.assertEqual(main.count('observerRoot='), 1)
        self.assertIn('finally { GC.KeepAlive(observerRoot); }', main)
        for forbidden in ('CloseReference', 'CloseHandle', 'Dispose', 'SetEvent', 'TryParse(args[1]'):
            self.assertNotIn(forbidden, text)

    def test_expanded_managed_host_keeps_real_parent_and_native_tests(self):
        text = RUNNER.read_text(encoding='utf-8')
        managed = text.split('function Invoke-ManagedContracts {', 1)[1].split('\n}', 1)[0]
        expected = {'NativePipeTransport.cs', 'NativePipeTransportTests.cs', 'NativePipeTransportNative.cs',
                    'NativeChildCapture.cs', 'NativeChildCaptureTests.cs', 'NativeChildCaptureNative.cs',
                    'NativeChildCaptureNativeTests.cs', 'NativeLaunchEnvironment.cs', 'NativeLaunchEnvironmentNative.cs',
                    'NativeSentinelObservation.cs', 'NativeSentinelObservationNative.cs', 'NativeSentinelObservationNativeTests.cs',
                    'NativeFixedImageIdentity.cs','NativeFixedFixtureCommand.cs','NativeFixedImageComposition.cs'}
        names = re.findall(r"'([A-Za-z]+\.cs)'", managed)
        self.assertEqual(set(names), expected)
        self.assertEqual(len(names), len(expected))


class NativeChildEvidenceContract(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='pvbox-child-json-')
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'native-child-capture.jsonl'

    def write(self, records):
        self.path.write_bytes(('\n'.join(json.dumps(record, separators=(',', ':'))
                                       for record in records) + '\n').encode('utf-8'))

    def refuses(self, records):
        self.write(records)
        with self.assertRaises(ValueError):
            validate_evidence(self.path)

    def test_accepts_complete_observations_without_mutation_authority(self):
        reports = sample_records()
        self.write(reports)
        observed = validate_evidence(self.path, require_pass=True)
        self.assertEqual(observed, reports)
        self.assertEqual(observed[4]['exit_code'], 259)
        self.assertEqual(observed[5]['overall'], 'UNKNOWN')
        self.assertTrue(all(record['mutation_authorized'] is False for record in observed))

    def test_failure_prefix_is_diagnostic_and_cannot_satisfy_pass(self):
        reports = sample_records()[:1]
        reports[0].update(status='FAIL', overall='UNKNOWN', exit_observed=False,
                          eof_stdout=False, eof_stderr=False, resources_released=False,
                          retained_owner=True, sentinel_probe=False)
        reports.append({'kind': 'native_child_summary', 'status': 'FAIL', 'cases': 1,
                        'failed': 1, 'all_owners_released': False, 'mutation_authorized': False})
        self.write(reports)
        self.assertEqual(validate_evidence(self.path), reports)
        with self.assertRaises(ValueError):
            validate_evidence(self.path, require_pass=True)

    def test_preflight_failure_does_not_require_invented_case(self):
        reports = [{'kind': 'native_child_summary', 'status': 'FAIL', 'cases': 0,
                    'failed': 1, 'all_owners_released': True, 'mutation_authorized': False}]
        self.write(reports)
        self.assertEqual(validate_evidence(self.path), reports)

    def test_requires_exact_record_fields(self):
        for index in (0, -1):
            for key in sample_records()[index]:
                reports = sample_records()
                del reports[index][key]
                with self.subTest(record=index, missing=key):
                    self.refuses(reports)
            reports = sample_records()
            reports[index]['receipt'] = 'release resources'
            with self.subTest(record=index, extra='receipt'):
                self.refuses(reports)

    def test_rejects_boolean_coercion_and_mutation_claims(self):
        fields = ('created', 'exit_observed', 'eof_stdout', 'eof_stderr',
                  'resources_released', 'retained_owner', 'sentinel_probe',
                  'sentinel_unsignaled', 'held_writer_blocked_eof', 'one_shot_refused',
                  'mutation_authorized')
        for field in fields:
            for value in (0, 1, 'false', None):
                reports = sample_records()
                reports[0][field] = value
                with self.subTest(field=field, value=value):
                    self.refuses(reports)
        for index in (0, -1):
            reports = sample_records()
            reports[index]['mutation_authorized'] = True
            with self.subTest(record=index, authority=True):
                self.refuses(reports)
        for value in (0, 1, 'true', None):
            reports = sample_records()
            reports[-1]['all_owners_released'] = value
            with self.subTest(summary_boolean=value):
                self.refuses(reports)

    def test_numeric_fields_require_bounded_integers_not_bools(self):
        for index, field, maximum in ((0, 'exit_code', 4294967295),
                                      (0, 'stdout_bytes', 300000), (0, 'stderr_bytes', 300000),
                                      (0, 'rounds', 32768), (0, 'fault_site', 3),
                                      (0, 'evidence_bytes_written', 1), (0, 'create_calls', 1),
                                      (0, 'wait_calls', 32768), (0, 'exit_code_reads', 32768),
                                      (0, 'create_error', 4294967295),
                                      (-1, 'cases', 9), (-1, 'failed', 9)):
            for value in (-1, maximum + 1, True, False, 1.0, '1', None):
                reports = sample_records()
                reports[index][field] = value
                with self.subTest(field=field, value=value):
                    self.refuses(reports)

    def test_assertion_diagnostics_allow_exception_marker_only_in_failed_case(self):
        for value in (-2, 65, True, False, 0.0, '0', None):
            reports = sample_records()
            reports[0]['assertion_failed_at'] = value
            with self.subTest(value=value):
                self.refuses(reports)
        for value in (-1, 64):
            reports = sample_records()
            reports[0].update(status='FAIL', assertion_failed_at=value, create_error=4294967295)
            reports[-1].update(status='FAIL', failed=1)
            self.write(reports)
            with self.subTest(valid_failure=value):
                self.assertEqual(validate_evidence(self.path), reports)
        for field, value in (('create_error', 1), ('assertion_failed_at', -1), ('assertion_failed_at', 1)):
            reports = sample_records()
            reports[0][field] = value
            with self.subTest(pass_field=field, value=value):
                self.refuses(reports)

    def test_channels_require_two_exact_bounded_records(self):
        for value in (None, True, {}, [], [{}], [{}, {}, {}]):
            reports = sample_records()
            reports[0]['channels'] = value
            with self.subTest(channels=value):
                self.refuses(reports)
        for channel in (0, 1):
            reports = sample_records()
            reports[0]['channels'][channel]['receipt'] = 'released'
            self.refuses(reports)
            for field, maximum in (('retained', 65536), ('discarded', 300000),
                                   ('read_issued', 32768), ('read_terminal', 32768),
                                   ('read_pending', 32768), ('read_immediate', 32768),
                                   ('read_visits', 32768), ('max_read_gap', 1)):
                reports = sample_records()
                del reports[0]['channels'][channel][field]
                with self.subTest(channel=channel, missing=field):
                    self.refuses(reports)
                for value in (-1, maximum + 1, True, False, 1.0, '1', None):
                    reports = sample_records()
                    reports[0]['channels'][channel][field] = value
                    with self.subTest(channel=channel, field=field, value=value):
                        self.refuses(reports)

    def test_pass_observes_fault_sites_native_calls_and_exact_channel_completion(self):
        for field, value in (('fault_site', 1), ('evidence_bytes_written', 1),
                             ('create_calls', 0), ('wait_calls', 0), ('exit_code_reads', 0)):
            reports = sample_records()
            reports[0][field] = value
            with self.subTest(field=field):
                self.refuses(reports)
        for index in (5, 6, 7):
            reports = sample_records()
            reports[index]['fault_site'] = 0
            with self.subTest(fault_case=index):
                self.refuses(reports)
        reports = sample_records()
        reports[7]['evidence_bytes_written'] = 0
        self.refuses(reports)
        for channel in (0, 1):
            for field, value in (('discarded', 1), ('read_terminal', 0), ('read_visits', 0)):
                reports = sample_records()
                reports[0]['channels'][channel][field] = value
                with self.subTest(channel=channel, field=field):
                    self.refuses(reports)
        for index in (6, 7):
            reports = sample_records()
            reports[index]['channels'][0].update(retained=8192, discarded=0)
            with self.subTest(missing_discard=index):
                self.refuses(reports)

    def test_rejects_noncanonical_hashes_and_unknown_enums(self):
        for field, values in (
                ('stdout_hash', ('0123456789ABCDEf', '0' * 15, '0' * 17, 'g' * 16, 1, None)),
                ('stderr_hash', ('\u0000' * 16, [], True)),
                ('case', ('Other', 'empty', '', [], None)),
                ('status', ('OK', 'pass', True, None)),
                ('overall', ('COMPLETE', 'observed', True, None)),
                ('kind', ('managed_child_contracts', 'native_pipe_case', [], None))):
            for value in values:
                reports = sample_records()
                reports[0][field] = value
                with self.subTest(field=field, value=value):
                    self.refuses(reports)

    def test_rejects_missing_duplicate_or_extra_cases_and_summary(self):
        complete = sample_records()
        variants = [complete[:-1], complete[1:], complete + [complete[-1]],
                    complete[:-1] + [complete[0], complete[-1]],
                    [complete[-1]] + complete[:-1],
                    complete[:2] + [complete[-1]] + complete[2:-1]]
        duplicate = copy.deepcopy(complete)
        duplicate[1]['case'] = 'Empty'
        variants.append(duplicate)
        for reports in variants:
            with self.subTest(records=len(reports)):
                self.refuses(reports)

    def test_summary_must_match_observed_records_and_status(self):
        for patch in ({'cases': 8}, {'failed': 1}, {'all_owners_released': False},
                      {'status': 'FAIL', 'failed': 0}, {'status': 'pass'}):
            reports = sample_records()
            reports[-1].update(patch)
            with self.subTest(patch=patch):
                self.refuses(reports)
        reports = sample_records()
        reports[0].update(status='FAIL', resources_released=False, retained_owner=True)
        reports[-1].update(status='FAIL', failed=1)
        self.refuses(reports)

    def test_pass_requires_independent_observations_not_status_alone(self):
        for field, value in (('created', False), ('exit_observed', False),
                             ('eof_stdout', False), ('eof_stderr', False),
                             ('resources_released', False), ('retained_owner', True),
                             ('sentinel_probe', False), ('sentinel_unsignaled', False),
                             ('one_shot_refused', False), ('rounds', 0),
                             ('held_writer_blocked_eof', True), ('overall', 'UNKNOWN')):
            reports = sample_records()
            reports[0][field] = value
            with self.subTest(field=field):
                self.refuses(reports)
        for index in (5, 6, 7, 8):
            reports = sample_records()
            reports[index]['overall'] = 'OBSERVED'
            with self.subTest(fault_case=index):
                self.refuses(reports)
        reports = sample_records()
        reports[8]['held_writer_blocked_eof'] = False
        self.refuses(reports)

    def test_failure_count_cannot_hide_reported_failed_cases(self):
        reports = sample_records()
        reports[0]['status'] = reports[1]['status'] = 'FAIL'
        reports[-1].update(status='FAIL', failed=1)
        self.refuses(reports)

    def test_rejects_unsafe_json_encodings_and_torn_records(self):
        self.write(sample_records())
        good = self.path.read_bytes()
        malformed = [
            good.replace(b'"mutation_authorized":false',
                         b'"mutation_authorized":false,"mutation_authorized":false', 1),
            good.replace(b'"rounds":1', b'"rounds":NaN', 1),
            good.replace(b'"rounds":1', b'"rounds":Infinity', 1),
            good.replace(b'"rounds":1', b'"rounds":-Infinity', 1),
            good.replace(b'"rounds":1', b'"rounds":1e9999', 1),
            good.replace(b'"retained":0', b'"retained":0,"retained":0', 1),
            good.replace(b'"Empty"', b'"\xff"', 1),
            b'\xef\xbb\xbf' + good, good[:-1], good + b'\n', b'', b'[]\n', b'null\n',
            b'[' * 1500 + b']' * 1500 + b'\n',
        ]
        for data in malformed:
            self.path.write_bytes(data)
            with self.subTest(size=len(data)), self.assertRaises(ValueError):
                validate_evidence(self.path)

    def test_rejects_record_and_artifact_size_overflow(self):
        for data in (b' ' * 4096 + b'{}\n', b' ' * 262145, b'{}\n' * 65):
            self.path.write_bytes(data)
            with self.subTest(size=len(data)), self.assertRaises(ValueError):
                validate_evidence(self.path)

    def test_validator_cli_distinguishes_diagnostics_from_success(self):
        self.write(sample_records())
        command = [sys.executable, str(Path(__file__).resolve()), '--validate-evidence', str(self.path)]
        result = subprocess.run(command + ['--require-pass'], text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('10 observational records', result.stdout)
        self.write([{'kind': 'native_child_summary', 'status': 'FAIL', 'cases': 0,
                     'failed': 1, 'all_owners_released': False, 'mutation_authorized': False}])
        result = subprocess.run(command, text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = subprocess.run(command + ['--require-pass'], text=True, capture_output=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)


@unittest.skipUnless(SHELL, 'PowerShell compiler required')
class NativeChildRunnerContract(unittest.TestCase):
    def run_runner(self, *arguments):
        return subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-File', str(RUNNER), *arguments],
                              text=True, capture_output=True, timeout=60)

    def test_managed_capture_decisions_without_native_launch(self):
        result = self.run_runner('-ManagedOnly')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('managed fixed-child contracts PASS', result.stdout)
        self.assertIn('managed sentinel native adapter PASS', result.stdout)
        for contract in ('arguments', 'protocol', 'observer'):
            self.assertIn('managed sentinel ' + contract + ' PASS', result.stdout)
        self.assertNotIn('native_child_summary', result.stdout)
        self.assertNotIn('native_child_case', result.stdout)

    def run_sentinel_contract(self, method, marker):
        # Compile the actual shared pure component and exercise each behavior group
        # separately so a parser failure cannot mask protocol/ownership failures.
        script = r'''
        $ErrorActionPreference='Stop'
        $root='__ROOT__'
        Add-Type -Path @('NativePipeTransport.cs','NativeChildCapture.cs',
            'NativeSentinelObservation.cs','NativeChildCaptureTests.cs' | ForEach-Object { Join-Path $root $_ })
        if ([PortableVBox.NativeChildCaptureTests]::__METHOD__() -ne 0) { throw 'Sentinel contract failed' }
        '''.replace('__ROOT__', str(ROOT / 'tests/windows').replace("'", "''")).replace('__METHOD__', method)
        result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-Command', script],
                                text=True, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(marker, result.stdout)
        self.assertNotIn('native_child_case', result.stdout)
        self.assertNotIn('native_child_summary', result.stdout)

    def test_actual_sentinel_arguments_are_pure_and_strict(self):
        self.run_sentinel_contract('RunSentinelArguments', 'managed sentinel arguments PASS')

    def test_actual_sentinel_protocol_validates_only_captured_prefix(self):
        self.run_sentinel_contract('RunSentinelProtocol', 'managed sentinel protocol PASS')

    def test_actual_sentinel_owner_uses_fake_queries_and_exact_owned_close(self):
        self.run_sentinel_contract('RunSentinelObserver', 'managed sentinel observer PASS')

    def run_native_sentinel_contract(self, method, marker):
        script = r'''
        $ErrorActionPreference='Stop'
        $root='__ROOT__'
        . (Join-Path $root 'NativeFixedFixtureBuild.ps1')
        $parent=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-direct-owner-build-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $parent | Out-Null
        $build=New-FixedFixtureBuild $parent
        $names=@('NativePipeTransport.cs','NativePipeTransportTests.cs','NativePipeTransportNative.cs',
            'NativeChildCapture.cs','NativeChildCaptureTests.cs','NativeChildCaptureNative.cs','NativeChildCaptureNativeTests.cs',
            'NativeLaunchEnvironment.cs','NativeLaunchEnvironmentNative.cs',
            'NativeSentinelObservation.cs','NativeSentinelObservationNative.cs','NativeSentinelObservationNativeTests.cs','NativeFixedImageIdentity.cs','NativeFixedFixtureCommand.cs','NativeFixedImageComposition.cs')
        Add-Type -Path @(Get-FixedFixtureConsumerSources $build $names)
        if ([PortableVBox.NativeSentinelObservationNativeTests]::__METHOD__() -ne 0) { throw 'Actual native-boundary contract failed' }
        '''.replace('__ROOT__', str(ROOT / 'tests/windows').replace("'", "''")).replace('__METHOD__', method)
        result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-Command', script],
                                text=True, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(marker, result.stdout)
        self.assertNotIn('native_child_case', result.stdout)
        self.assertNotIn('native_child_summary', result.stdout)

    def test_actual_native_sentinel_adapter_captures_order_and_unavailable_returns(self):
        self.run_native_sentinel_contract('RunQueryAdapter', 'managed sentinel query adapter PASS')

    def test_actual_parent_fresh_sentinel_and_refused_launch_without_native_calls(self):
        self.run_native_sentinel_contract('RunFreshParent', 'managed sentinel fresh parent PASS')

    def test_actual_parent_rejects_nonexcluded_capture_and_expected_helper_is_independent(self):
        self.run_native_sentinel_contract('RunCapturedSentinel', 'managed sentinel capture composition PASS')

    def test_actual_child_output_is_empty_or_exact_pvc2_and_keeps_observer_root(self):
        # Compile and call the real fixed child in a managed host, replacing only
        # its bounded output sink. No native observation or EXE execution occurs.
        harness = r'''
        using System;
        using System.Reflection;
        namespace PortableVBox {
         public static class ChildOutputContracts {
          const string Token="0123456789abcdef0123456789abcdef";
          public static void Run() {
           var rootField=typeof(NativeCaptureFixtureChild).GetField("observerRoot",BindingFlags.Static|BindingFlags.NonPublic);
           if(rootField==null) throw new Exception("actual child must retain a static observerRoot");
           foreach(string mode in new[]{"Empty","Binary","Large","Nonzero","Exit259","PostCreateFault","CaptureFault","EvidenceFault","WithheldEof"})
           foreach(SentinelResult result in new[]{SentinelResult.Unknown,SentinelResult.Excluded,SentinelResult.SameObject}) {
            SentinelArguments parsed;int rejection;
            if(!SentinelArguments.TryParse(new[]{mode,"17",Token},out parsed,out rejection)) throw new Exception("parse");
            var root=new SentinelObserver(parsed);rootField.SetValue(null,root);
            int writes=0,a=0,b=0;ulong ah=14695981039346656037UL,bh=ah;
            int code=NativeCaptureFixtureChild.EmitObserved(parsed,result,delegate(bool err,byte[] bytes,int count) {
             ++writes;if(count<1 || count>bytes.Length) throw new Exception("bounded write");
             if(err) { b+=count;for(int i=0;i<count;i++) bh=unchecked((bh^bytes[i])*1099511628211UL); }
             else { a+=count;for(int i=0;i<count;i++) ah=unchecked((ah^bytes[i])*1099511628211UL); }
            });
            if(!Object.ReferenceEquals(root,rootField.GetValue(null))) throw new Exception("observer root changed after output");
            Console.WriteLine(mode+","+(int)result+","+code+","+writes+","+a+","+b+","+ah.ToString("x16")+","+bh.ToString("x16"));
            if(mode=="Empty" && writes!=0) throw new Exception("Empty made writes");
            if(mode!="Empty") {
             int failed=NativeCaptureFixtureChild.EmitObserved(parsed,result,delegate { throw new Exception("controlled write fault"); });
             if(failed!=93 || !Object.ReferenceEquals(root,rootField.GetValue(null))) throw new Exception("exception return/root");
            }
           }
           var main=typeof(NativeCaptureFixtureChild).GetMethod("Main",BindingFlags.Static|BindingFlags.NonPublic);
           if((int)main.Invoke(null,new object[]{new string[0]})!=90) throw new Exception("actual child uses parser shape rejection");
           if((int)main.Invoke(null,new object[]{new[]{"Other","17",Token}})!=91) throw new Exception("actual child parser case rejection");
           if((int)main.Invoke(null,new object[]{new[]{"Empty","01",Token}})!=92) throw new Exception("actual child canonical candidate rejection");
          }
         }
        }
        '''
        with tempfile.TemporaryDirectory(prefix='pvbox-child-output-') as directory:
            source = Path(directory) / 'ChildOutputContracts.cs'
            source.write_text(harness, encoding='utf-8')
            script = r'''
            $ErrorActionPreference='Stop'
            $root='__ROOT__'
            $sources=@('NativeCaptureFixtureChild.cs','NativeLaunchEnvironmentObservation.cs',
                'NativeSentinelObservation.cs','NativeSentinelObservationNative.cs' | ForEach-Object { Join-Path $root $_ })
            Add-Type -Path @($sources + '__HARNESS__')
            [PortableVBox.ChildOutputContracts]::Run()
            '''.replace('__ROOT__', str(ROOT / 'tests/windows').replace("'", "''")).replace('__HARNESS__', str(source).replace("'", "''"))
            result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-Command', script],
                                    text=True, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(len(lines), 27, result.stdout)
        for line in lines:
            mode, semantic, exit_code, writes, stdout_size, stderr_size, stdout_hash, stderr_hash = line.split(',')
            semantic, exit_code, writes = int(semantic), int(exit_code), int(writes)
            if mode == 'Empty':
                self.assertEqual((exit_code, writes, int(stdout_size), int(stderr_size)),
                                 (0 if semantic == 1 else 94, 0, 0, 0))
                self.assertEqual(stdout_hash, 'cbf29ce484222325')
                self.assertEqual(stderr_hash, 'cbf29ce484222325')
                continue
            body = 196731 if mode in ('Large', 'CaptureFault', 'EvidenceFault') else 4097 if mode == 'Binary' else 17
            stderr_body = 204829 if mode in ('Large', 'CaptureFault', 'EvidenceFault') else 257
            self.assertEqual(exit_code, 259 if mode == 'Exit259' else 23 if mode == 'Nonzero' else 0)
            self.assertGreater(writes, 0)
            self.assertEqual((int(stdout_size), int(stderr_size)), (body + 8, stderr_body))
            data = bytes((80, 86, 67, 50, semantic, 0, 0, 165)) + bytes((i * 31) & 255 for i in range(body))
            value = 14695981039346656037
            for byte in data:
                value = ((value ^ byte) * 1099511628211) & ((1 << 64) - 1)
            self.assertEqual(stdout_hash, format(value, '016x'))
            self.assertEqual(stderr_hash, expected_hash(stderr_body, 71))

    def test_native_report_serializer_matches_schema_without_native_calls(self):
        # Exercise the actual C# serializer on a never-run owner. This is only a
        # managed contract, not a successful native case or resource-release proof.
        script = r'''
        $ErrorActionPreference='Stop'
        $root='__ROOT__'
        . (Join-Path $root 'NativeFixedFixtureBuild.ps1')
        $parent=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-direct-owner-build-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $parent | Out-Null
        $build=New-FixedFixtureBuild $parent
        $names=@('NativePipeTransport.cs','NativePipeTransportTests.cs','NativePipeTransportNative.cs',
            'NativeChildCapture.cs','NativeSentinelObservation.cs','NativeSentinelObservationNative.cs','NativeChildCaptureNative.cs','NativeChildCaptureNativeTests.cs','NativeLaunchEnvironment.cs','NativeLaunchEnvironmentNative.cs','NativeFixedImageIdentity.cs','NativeFixedFixtureCommand.cs','NativeFixedImageComposition.cs')
        Add-Type -Path @(Get-FixedFixtureConsumerSources $build $names)
        $assembly=[PortableVBox.NativePipeTransportTests].Assembly
        $ownerType=$assembly.GetType('PortableVBox.ChildCaptureOwner',$true)
        $caseType=$assembly.GetType('PortableVBox.CaptureCase',$true)
        $flags=[Reflection.BindingFlags]'Instance,NonPublic'
        $constructor=$ownerType.GetConstructor($flags,$null,[type[]]@($caseType),$null)
        $owner=$constructor.Invoke([object[]]@([Enum]::Parse($caseType,'Empty')))
        Write-Output $ownerType.GetMethod('Report',$flags).Invoke($owner,[object[]]@($false))
        '''.replace('__ROOT__', str(ROOT / 'tests/windows').replace("'", "''"))
        result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-Command', script],
                                text=True, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(len(lines), 1, result.stdout)
        report = strict_json(lines[0])
        self.assertIs(report['created'], False)
        self.assertEqual((report['create_calls'], report['wait_calls'], report['exit_code_reads']), (0, 0, 0))
        summary = {'kind': 'native_child_summary', 'status': 'FAIL', 'cases': 1,
                   'failed': 1, 'all_owners_released': False, 'mutation_authorized': False}
        with tempfile.TemporaryDirectory(prefix='pvbox-child-serializer-') as root:
            path = Path(root) / 'managed-serializer-only.jsonl'
            path.write_bytes((lines[0] + '\n' + json.dumps(summary) + '\n').encode('utf-8'))
            self.assertEqual(validate_evidence(path), [report, summary])

    def test_linux_skip_is_explicit_and_has_no_evidence_side_effect(self):
        if os.name == 'nt':
            self.skipTest('Native execution belongs to the Windows runner')
        with tempfile.TemporaryDirectory(prefix='pvbox-child-skip-') as root:
            evidence = Path(root) / 'absent'
            result = self.run_runner('-EvidenceDirectory', str(evidence))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('SKIP native child capture: Windows required', result.stdout)
            self.assertNotIn('native_child_case', result.stdout)
            self.assertFalse(evidence.exists())

    def test_serialized_report_and_external_command_inputs_are_rejected(self):
        for argument, value in (('-ResumeEvidence', '{"mutation_authorized":true}'),
                                ('-Executable', 'untrusted.exe'), ('-ChildArguments', 'anything')):
            result = self.run_runner('-ManagedOnly', argument, value)
            with self.subTest(argument=argument):
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('managed fixed-child contracts PASS', result.stdout)


if __name__ == '__main__':
    if len(sys.argv) in (3, 4) and sys.argv[1] == '--validate-evidence':
        if len(sys.argv) == 4 and sys.argv[3] != '--require-pass':
            raise SystemExit('Unsupported evidence validation option')
        reports = validate_evidence(sys.argv[2], require_pass=len(sys.argv) == 4)
        print('PASS strict bounded UTF-8 JSONL: %d observational records; no mutation authority' % len(reports))
    else:
        unittest.main()
