"""Test-only explicit environment contracts; diagnostics never grant authority."""
import base64
import binascii
import struct
import unicodedata
import copy
import json
import math
import sys
import tempfile
import os
from pathlib import Path
import shutil
import subprocess
import unittest
ROOT = Path(__file__).resolve().parents[1]
SHELL = os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh')

@unittest.skipUnless(SHELL, 'PowerShell compiler required')
class EnvironmentManagedContract(unittest.TestCase):
    def test_legacy_constructor_rejects_appended_mode_before_native_entry(self):
        script = r'''
$ErrorActionPreference='Stop'
$root='__ROOT__'
$sources=@('NativePipeTransport.cs','NativePipeTransportTests.cs','NativePipeTransportNative.cs','NativeChildCapture.cs','NativeSentinelObservation.cs','NativeSentinelObservationNative.cs','NativeChildCaptureNative.cs','NativeChildCaptureNativeTests.cs','NativeLaunchEnvironment.cs','NativeLaunchEnvironmentNative.cs') | ForEach-Object { Join-Path $root $_ }
Add-Type -Path $sources
$a=[PortableVBox.NativePipeTransportTests].Assembly
$t=$a.GetType('PortableVBox.ChildCaptureOwner',$true)
$e=$a.GetType('PortableVBox.CaptureCase',$true)
$c=$t.GetConstructor([Reflection.BindingFlags]'Instance,NonPublic',$null,[type[]]@($e),$null)
foreach($value in @(-1,9,2147483647)) {
 $rejected=$false
 try { $null=$c.Invoke([object[]]@([Enum]::ToObject($e,$value))) } catch { if($_.Exception.InnerException -is [ArgumentOutOfRangeException]) { $rejected=$true } }
 if(-not $rejected) { throw 'ASSERT legacy constructor accepted a non-baseline case' }
}
$sinkType=$a.GetType('PortableVBox.EnvironmentEvidenceSink',$true)
$sink=New-Object IO.MemoryStream
$success=$sinkType.GetMethod('TryWrite',[Reflection.BindingFlags]'Static,NonPublic').Invoke($null,[object[]]@([IO.Stream]$sink))
if($success -or $sink.Length -ne 1) { throw 'ASSERT diagnostic fault must return failure after one byte' }
Write-Output 'legacy constructor closed PASS'
'''.replace('__ROOT__', str(ROOT/'tests/windows').replace("'", "''"))
        result=subprocess.run([SHELL,'-NoProfile','-NonInteractive','-Command',script],capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('legacy constructor closed PASS',result.stdout)



CASES = ('None', 'AfterCreate', 'Evidence')
CASE_BOOLS = frozenset(('created', 'exit_observed', 'eof_stdout', 'eof_stderr',
    'resources_released', 'retained_owner', 'environment_released', 'parent_sentinel',
    'restored', 'observed_fields', 'one_shot_refused', 'sentinel_probe', 'sentinel_unsignaled',
    'mutation_authorized'))
NUMBERS = {'create_calls': 1, 'stdout_bytes': 16392, 'stderr_bytes': 16392,
           'fault_site': 3, 'evidence_bytes_written': 1, 'fault_at_bytes': 16392,
           'exit_code': 4294967295}
CASE_FIELDS = CASE_BOOLS | frozenset(NUMBERS) | frozenset(('kind', 'case', 'status', 'overall', 'create_state', 'observation_base64', 'expected_directory_base64'))
SUMMARY_FIELDS = frozenset(('kind', 'status', 'cases', 'failed', 'all_owners_released',
                            'sentinel_restored', 'mutation_authorized'))

def fixture_record(values=None):
    # Independent byte fixture, not the C# codec and not native evidence.
    if values is None: values=(None,'Привет = fixture 🙂','','C:\\Windows','C:\\Windows')
    body=b'';flags=0
    for index,value in enumerate(values):
        if value is not None: flags|=1<<index
        raw=b'' if value is None else value.encode('utf-16-le')
        body+=struct.pack('<I',len(raw))+raw
    return struct.pack('<4sHHI',b'PVE1',1,flags,12+len(body))+body

def encoded(raw): return base64.b64encode(raw).decode('ascii')

def samples():
    """Synthetic schema fixtures only, never native execution evidence."""
    records=[]
    for index, case in enumerate(CASES):
        record = {key: True for key in CASE_BOOLS}
        record.update(kind='native_environment_case', case=case, status='PASS',
                      overall='OBSERVED' if index == 0 else 'UNKNOWN', create_state='ReturnedTrue',
                      retained_owner=False, mutation_authorized=False, create_calls=1,
                      stdout_bytes=len(fixture_record())+8, stderr_bytes=0, fault_site=(0, 1, 3)[index],
                      evidence_bytes_written=1 if index == 2 else 0,
                      fault_at_bytes=16 if index == 2 else 0, exit_code=0,
                      observation_base64=encoded(fixture_record()),
                      expected_directory_base64=encoded('C:\\Windows'.encode('utf-16-le')))
        records.append(record)
    records.append(dict(kind='native_environment_summary', status='PASS', cases=3, failed=0,
                        all_owners_released=True, sentinel_restored=True, mutation_authorized=False))
    return records

def strict_json(line):
    def pairs(items):
        result={}
        for key, value in items:
            if key in result: raise ValueError('Duplicate JSON key')
            result[key]=value
        return result
    def invalid(value): raise ValueError('Nonfinite JSON number')
    def finite(value):
        number=float(value)
        if not math.isfinite(number): invalid(value)
        return number
    try:
        return json.loads(line,object_pairs_hook=pairs,parse_constant=invalid,parse_float=finite)
    except RecursionError as error:
        raise ValueError('Evidence nesting bound') from error

def bounded(record, field, maximum):
    value=record[field]
    if type(value) is not int or not 0 <= value <= maximum:
        raise ValueError('Invalid bounded integer: '+field)

def decode_canonical(value, maximum):
    if value is None: return None
    if type(value) is not str or len(value)>4*((maximum+2)//3):
        raise ValueError('Invalid bounded base64 evidence')
    try: raw=base64.b64decode(value,validate=True)
    except (ValueError,binascii.Error) as error: raise ValueError('Invalid base64 evidence') from error
    if len(raw)>maximum or encoded(raw)!=value: raise ValueError('Noncanonical or oversized base64 evidence')
    return raw

def decode_utf16(raw):
    if len(raw)%2: raise ValueError('Odd UTF16 evidence length')
    value=raw.decode('utf-16-le',errors='strict')
    if '\0' in value: raise ValueError('NUL in UTF16 evidence')
    return value

def validate_directory(raw):
    value=decode_utf16(raw)
    if not 6<=len(raw)<=518 or len(value)<3 or value[0] not in 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz' or value[1:3]!=':\\':
        raise ValueError('Unsupported expected OS directory')
    if any(unicodedata.category(c)=='Cc' or c=='/' for c in value): raise ValueError('Invalid directory character')
    if len(value)>3:
        for component in value[3:].split('\\'):
            if not component or component in ('.','..') or component[-1] in ' .' or any(c in '<>:"|?*' for c in component):
                raise ValueError('Unsupported directory component')
    return value

def parse_observation(raw):
    """Independent PVE1 reader. Actual fields are compared outside this parser."""
    if type(raw) is not bytes or not 32<=len(raw)<=16384: raise ValueError('PVE1 record size bound')
    magic,version,flags,total=struct.unpack_from('<4sHHI',raw)
    if magic!=b'PVE1' or version!=1 or flags&~31 or total!=len(raw): raise ValueError('Invalid PVE1 header')
    values=[];at=12
    for index in range(5):
        if at+4>len(raw): raise ValueError('Truncated PVE1 field length')
        length=struct.unpack_from('<I',raw,at)[0];at+=4
        present=bool(flags&(1<<index))
        if length>8192 or length%2 or length>len(raw)-at or (not present and length): raise ValueError('Invalid PVE1 field length/presence')
        values.append(decode_utf16(raw[at:at+length]) if present else None)
        at+=length
    if at!=len(raw): raise ValueError('Trailing PVE1 bytes')
    return tuple(values)

def validate_case(record):
    if set(record) != CASE_FIELDS: raise ValueError('Unexpected case fields')
    if type(record['case']) is not str or record['case'] not in CASES: raise ValueError('Unknown case')
    if type(record['overall']) is not str or record['overall'] not in ('OBSERVED','UNKNOWN'): raise ValueError('Unknown observation state')
    if type(record['create_state']) is not str or record['create_state'] not in ('NotEntered','EnteredReturnUnknown','ReturnedFalse','ReturnedTrue'):
        raise ValueError('Unknown create state')
    for field in CASE_BOOLS:
        if type(record[field]) is not bool: raise ValueError('Invalid boolean: '+field)
    for field, maximum in NUMBERS.items(): bounded(record,field,maximum)
    actual=decode_canonical(record['observation_base64'],1536)
    directory_raw=decode_canonical(record['expected_directory_base64'],518)
    directory=None if directory_raw is None else validate_directory(directory_raw)
    if record['observed_fields']:
        if actual is None or directory is None: raise ValueError('Observed fields require actual bytes and OS query expectation')
        values=parse_observation(actual)
        if values!=(None,'Привет = fixture 🙂','',directory,directory): raise ValueError('Actual environment differs from fixed policy')
        if len(actual)+8!=record['stdout_bytes']: raise ValueError('Actual record does not cover captured stdout')
    if record['resources_released'] == record['retained_owner']: raise ValueError('Contradictory owner release')
    if record['resources_released'] and not record['environment_released']: raise ValueError('Environment memory still retained')
    if record['create_state']=='NotEntered' and record['create_calls']!=0: raise ValueError('Contradictory native entry')
    if record['create_state']!='NotEntered' and record['create_calls']!=1: raise ValueError('Missing native entry')
    if record['created'] != (record['create_state']=='ReturnedTrue'): raise ValueError('Contradictory create return')
    if record['create_state']=='EnteredReturnUnknown' and (record['environment_released'] or record['resources_released']):
        raise ValueError('Unknown create cannot release')
    if record['status']=='PASS':
        index=CASES.index(record['case'])
        expected='OBSERVED' if index==0 else 'UNKNOWN'
        if record['overall']!=expected: raise ValueError('Unexpected observation state')
        required=CASE_BOOLS-frozenset(('retained_owner','mutation_authorized'))
        if not all(record[field] for field in required): raise ValueError('Missing independent observation')
        if record['create_state']!='ReturnedTrue' or record['create_calls']!=1 or record['exit_code']!=0:
            raise ValueError('Missing known successful native return/exit')
        if not 40 <= record['stdout_bytes'] <= 16392 or record['stderr_bytes']!=0: raise ValueError('Invalid captured record size')
        if record['fault_site']!=(0,1,3)[index]: raise ValueError('Expected fault not observed')
        if record['evidence_bytes_written']!=(1 if index==2 else 0): raise ValueError('Diagnostic write mismatch')
        if index==2:
            if not 8 <= record['fault_at_bytes'] < record['stdout_bytes']: raise ValueError('Fault must precede final fragment')
        elif record['fault_at_bytes']!=0: raise ValueError('Unexpected diagnostic fault position')

def validate_evidence(path, require_pass=False):
    """Validate bounded text diagnostics only; never authorize native resource release."""
    path=Path(path)
    if not 0 < path.stat().st_size <= 16384: raise ValueError('Artifact size bound')
    records=[]; summary=None; cases=[]; total=0
    with path.open('rb') as stream:
        while True:
            line=stream.readline(4097)
            if not line: break
            total+=len(line)
            if len(line)>4096 or total>16384 or len(records)>=4 or not line.endswith(b'\n'):
                raise ValueError('Record size/count bound or torn line')
            record=strict_json(line.decode('utf8',errors='strict'))
            if type(record) is not dict or record.get('mutation_authorized') is not False:
                raise ValueError('Evidence cannot authorize mutation')
            if type(record.get('status')) is not str or record['status'] not in ('PASS','FAIL') or summary is not None:
                raise ValueError('Unknown status or record after summary')
            if record.get('kind')=='native_environment_case':
                validate_case(record)
                if len(cases)>=3 or record['case']!=CASES[len(cases)]: raise ValueError('Repeated or unordered case')
                cases.append(record)
            elif record.get('kind')=='native_environment_summary':
                if set(record)!=SUMMARY_FIELDS: raise ValueError('Unexpected summary fields')
                bounded(record,'cases',3); bounded(record,'failed',16)
                if type(record['all_owners_released']) is not bool or type(record['sentinel_restored']) is not bool:
                    raise ValueError('Invalid summary booleans')
                summary=record
            else: raise ValueError('Unknown record kind')
            records.append(record)
    if summary is None or summary['cases']!=len(cases): raise ValueError('Missing summary or case count mismatch')
    if summary['failed'] < sum(record['status']=='FAIL' for record in cases): raise ValueError('Hidden case failure')
    if summary['all_owners_released'] and any(not r['resources_released'] for r in cases): raise ValueError('Summary hides retained owner')
    if summary['sentinel_restored'] and any(not r['restored'] for r in cases): raise ValueError('Summary hides unrestored sentinel')
    if summary['status']=='PASS':
        if len(cases)!=3 or summary['failed']!=0 or not summary['all_owners_released'] or not summary['sentinel_restored']:
            raise ValueError('PASS requires all three complete observations')
    elif summary['failed']==0: raise ValueError('FAIL requires a failed check')
    if require_pass and summary['status']!='PASS': raise ValueError('Failure diagnostics cannot pass')
    return records

class EnvironmentEvidenceContract(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory(prefix='pvbox-environment-evidence-')
        self.addCleanup(self.directory.cleanup)
        self.path=Path(self.directory.name)/'native-launch-environment.jsonl'
    def write(self, records):
        self.path.write_bytes(('\n'.join(json.dumps(r,separators=(',',':')) for r in records)+'\n').encode('utf8'))
    def refuses(self, records):
        self.write(records)
        with self.assertRaises(ValueError): validate_evidence(self.path)
    def test_accepts_complete_diagnostic_observations(self):
        self.write(samples())
        self.assertEqual(validate_evidence(self.path,True),samples())
    def test_rejects_mutation_claims(self):
        for index in (0,-1):
            records=samples(); records[index]['mutation_authorized']=True
            self.refuses(records)



    def test_rejects_changed_actual_unicode_even_when_flag_claims_success(self):
        records=samples()
        records[0]['observation_base64']=encoded(fixture_record((None,'changed','','C:\\Windows','C:\\Windows')))
        self.refuses(records)

    def test_independent_parser_rejects_byte_mutations(self):
        raw=fixture_record()
        mutations=[raw[:n] for n in range(len(raw))]
        for offset,value in ((0,0),(4,2),(5,1),(6,255),(7,1),(8,0),(12,2),(16,1),(20,0)):
            changed=bytearray(raw);changed[offset]=value;mutations.append(bytes(changed))
        changed=bytearray(raw);changed[20:22]=b'\x00\xd8';mutations.append(bytes(changed))
        changed=bytearray(raw);changed[16:20]=struct.pack('<I',0xffffffff);mutations.append(bytes(changed))
        changed=bytearray(raw+b'\0\0');changed[8:12]=struct.pack('<I',len(changed));mutations.append(bytes(changed))
        for values in (('', 'Привет = fixture 🙂','','C:\\Windows','C:\\Windows'),
                       (None,'Привет = fixture 🙂',None,'C:\\Windows','C:\\Windows'),
                       (None,'Привет = fixture 🙂','','C:\\Other','C:\\Windows'),
                       (None,'Привет = fixture 🙂','','C:\\Windows','C:\\Other')):
            mutations.append(fixture_record(values))
        for index,changed in enumerate(mutations):
            records=samples();records[0]['observation_base64']=encoded(changed);records[0]['stdout_bytes']=len(changed)+8
            with self.subTest(mutation=index): self.refuses(records)
    def test_evidence_base64_is_typed_canonical_and_bounded(self):
        for field in ('observation_base64','expected_directory_base64'):
            for value in (None,0,False,[],{},'', '!', 'é', 'AB==', 'AA==\n', 'AA=', 'AAAA=', encoded(b'x'*1537)):
                records=samples();records[0][field]=value
                with self.subTest(field=field,value=str(value)[:20]): self.refuses(records)
    def test_directory_expectation_is_bounded_supported_strict_utf16(self):
        for value in ('C:',r'\\server\Windows',r'\\?\C:\Windows','C:/Windows','C:\\A\\',
                      'C:\\A.','C:\\A ','C:\\.','C:\\..','C:\\A?','C:\\A\0B','C:\\'+('x'*257)):
            records=samples();records[0]['expected_directory_base64']=encoded(value.encode('utf-16-le'))
            with self.subTest(directory=value): self.refuses(records)
        for raw in (b'\x00',b'\x00\xd8',b'\x00\xdc'):
            records=samples();records[0]['expected_directory_base64']=encoded(raw);self.refuses(records)
        for directory in ('C:\\','C:\\'+('x'*256),'C:\\Каталог 🙂'):
            records=samples()
            for record in records[:-1]:
                raw=fixture_record((None,'Привет = fixture 🙂','',directory,directory))
                record.update(observation_base64=encoded(raw),expected_directory_base64=encoded(directory.encode('utf-16-le')),stdout_bytes=len(raw)+8)
            self.write(records);self.assertEqual(validate_evidence(self.path,True),records)
    def test_failure_can_preserve_malformed_actual_without_claiming_observation(self):
        records=samples();records[0].update(status='FAIL',observed_fields=False,observation_base64=encoded(b'broken'))
        records[-1].update(status='FAIL',failed=1)
        self.write(records);self.assertEqual(validate_evidence(self.path),records)
        records[0]['observed_fields']=True;self.refuses(records)
        records[0]['observed_fields']=False
        for value in (None,encoded(b'x'*1536)):
            records[0]['observation_base64']=value;self.write(records);self.assertEqual(validate_evidence(self.path),records)
        records[0]['observation_base64']=encoded(b'x'*1537);self.refuses(records)
        records[0]['observation_base64']='AB==';self.refuses(records)
        records[0]['observation_base64']=None;records[0]['expected_directory_base64']=None
        self.write(records);self.assertEqual(validate_evidence(self.path),records)
    def test_observed_fields_in_failed_lifetime_case_still_require_actual_match(self):
        records=samples();records[0].update(status='FAIL',restored=False)
        records[-1].update(status='FAIL',failed=1,sentinel_restored=False)
        self.write(records);self.assertEqual(validate_evidence(self.path),records)
        records[0]['observation_base64']=encoded(fixture_record((None,'wrong','','C:\\Windows','C:\\Windows')))
        self.refuses(records)
    def test_generic_parser_bounds_do_not_expand_wire_allowance(self):
        raw=fixture_record(('x'*4096,'y'*4080,None,None,None))
        self.assertEqual(len(raw),16384)
        self.assertEqual(parse_observation(raw),('x'*4096,'y'*4080,None,None,None))
        with self.assertRaises(ValueError): parse_observation(fixture_record(('x'*4096,'y'*4081,None,None,None)))
        with self.assertRaises(ValueError): parse_observation(fixture_record(('x'*4097,None,None,None,None)))
        records=samples();records[0]['observation_base64']=encoded(raw);self.refuses(records)

    def test_exact_fields(self):
        for index in (0,-1):
            for key in samples()[index]:
                records=samples();del records[index][key]
                with self.subTest(index=index,missing=key): self.refuses(records)
            records=samples();records[index]['authority']='release';self.refuses(records)
    def test_boolean_types(self):
        for index, fields in ((0,CASE_BOOLS),(-1,('all_owners_released','sentinel_restored','mutation_authorized'))):
            for field in fields:
                for value in (0,1,'false',None,[],{}):
                    records=samples();records[index][field]=value
                    with self.subTest(field=field,value=value): self.refuses(records)
    def test_numeric_types_and_bounds(self):
        for index, fields in ((0,NUMBERS),(-1,{'cases':3,'failed':16})):
            for field,maximum in fields.items():
                for value in (-1,maximum+1,True,False,1.0,'1',None,[],{}):
                    records=samples();records[index][field]=value
                    with self.subTest(field=field,value=value): self.refuses(records)
    def test_pass_requires_every_independent_fact(self):
        for field in CASE_BOOLS-frozenset(('retained_owner','mutation_authorized')):
            records=samples();records[0][field]=False
            with self.subTest(field=field): self.refuses(records)
        for field,value in (('create_calls',0),('create_state','ReturnedFalse'),('exit_code',1),('stdout_bytes',39),
                            ('stderr_bytes',1),('fault_site',1),('evidence_bytes_written',1),('fault_at_bytes',8),('overall','UNKNOWN')):
            records=samples();records[0][field]=value
            with self.subTest(field=field): self.refuses(records)
        for index in (1,2):
            records=samples();records[index]['overall']='OBSERVED';self.refuses(records)
            records=samples();records[index]['fault_site']=0;self.refuses(records)
        for field,value in (('evidence_bytes_written',0),('fault_at_bytes',0),('fault_at_bytes',192)):
            records=samples();records[2][field]=value;self.refuses(records)
    def test_unknown_enums_and_nonstring_types(self):
        for index,field in ((0,'kind'),(0,'case'),(0,'status'),(0,'overall'),(0,'create_state'),(-1,'kind'),(-1,'status')):
            for value in ('unrecognized',None,[],{},False,1):
                records=samples();records[index][field]=value
                with self.subTest(index=index,field=field,value=value): self.refuses(records)
    def test_failure_prefix_and_preflight_are_diagnostic_only(self):
        records=samples()[:1]
        records[0].update(status='FAIL',overall='UNKNOWN',create_state='NotEntered',created=False,
                          create_calls=0,resources_released=False,retained_owner=True,environment_released=False,restored=False)
        records.append(dict(kind='native_environment_summary',status='FAIL',cases=1,failed=1,
                            all_owners_released=False,sentinel_restored=False,mutation_authorized=False))
        self.write(records);self.assertEqual(validate_evidence(self.path),records)
        with self.assertRaises(ValueError): validate_evidence(self.path,True)
        records[-1].update(cases=0,all_owners_released=True,sentinel_restored=True)
        self.write(records[-1:]);self.assertEqual(validate_evidence(self.path),records[-1:])
        with self.assertRaises(ValueError): validate_evidence(self.path,True)
    def test_summary_cannot_hide_missing_failures_or_retention(self):
        for field,value in (('cases',2),('failed',1),('all_owners_released',False),('sentinel_restored',False),('status','FAIL')):
            records=samples();records[-1][field]=value;self.refuses(records)
        for field in ('resources_released','restored'):
            records=samples();records[0].update(status='FAIL',overall='UNKNOWN');records[0][field]=False
            if field=='resources_released': records[0]['retained_owner']=True
            records[-1].update(status='FAIL',failed=1);self.refuses(records)
        records=samples();records[0]['status']='FAIL';self.refuses(records)
    def test_record_order_duplicates_and_missing_summary(self):
        records=samples();records[1]=copy.deepcopy(records[0]);self.refuses(records)
        records=samples();records[0],records[1]=records[1],records[0];self.refuses(records)
        self.refuses(samples()[:-1]);self.refuses(samples()+[samples()[0]])
        self.refuses(samples()[-1:]+samples()[:-1])
    def test_unknown_native_return_cannot_claim_release(self):
        records=samples();records[0].update(status='FAIL',overall='UNKNOWN',create_state='EnteredReturnUnknown',created=False)
        records[-1].update(status='FAIL',failed=1);self.refuses(records)
    def test_strict_json_and_bounded_utf8_stream(self):
        self.write(samples());valid=self.path.read_bytes()
        bad=(b'',valid[:-1],b'\xff\n',b'{}\n',b'[]\n',b'null\n',b' '*4096+b'\n',b' '*16385,
             valid.replace(b'"create_calls":1',b'"create_calls":NaN',1),
             valid.replace(b'"create_calls":1',b'"create_calls":Infinity',1),
             valid.replace(b'"create_calls":1',b'"create_calls":1e999',1),
             valid.replace(b'"create_calls":1',b'"create_calls":1,"create_calls":1',1),
             b'['*2000+b']'*2000+b'\n')
        for index,data in enumerate(bad):
            self.path.write_bytes(data)
            with self.subTest(index=index), self.assertRaises(ValueError): validate_evidence(self.path)

@unittest.skipUnless(SHELL,'PowerShell compiler required')
class EnvironmentRunnerContract(unittest.TestCase):
    def run_runner(self,*arguments):
        return subprocess.run([SHELL,'-NoProfile','-NonInteractive','-File',str(ROOT/'tests/windows/check_native_launch_environment.ps1'),*arguments],
                              capture_output=True,text=True,timeout=60)
    def test_managed_suite_does_not_launch(self):
        result=self.run_runner('-ManagedOnly')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('managed environment integration PASS',result.stdout)
        self.assertNotIn('native_environment_case',result.stdout)
    def test_linux_skip_has_no_evidence_side_effect(self):
        if os.name=='nt': self.skipTest('Native execution belongs to Windows runner')
        with tempfile.TemporaryDirectory(prefix='pvbox-environment-skip-') as root:
            target=Path(root)/'absent';result=self.run_runner('-EvidenceDirectory',str(target))
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn('SKIP native launch environment: Windows required',result.stdout)
            self.assertFalse(target.exists())
    def test_actual_native_serializer_emits_valid_failure_diagnostics(self):
        script=r"""
$ErrorActionPreference='Stop'
$root='__ROOT__'
$sources=@('NativePipeTransport.cs','NativePipeTransportTests.cs','NativePipeTransportNative.cs',
 'NativeChildCapture.cs','NativeSentinelObservation.cs','NativeSentinelObservationNative.cs','NativeChildCaptureNative.cs','NativeChildCaptureNativeTests.cs',
 'NativeLaunchEnvironment.cs','NativeLaunchEnvironmentNative.cs','NativeLaunchEnvironmentObservation.cs',
 'NativeLaunchEnvironmentObservationTests.cs','NativeLaunchEnvironmentNativeTests.cs','NativeLaunchEnvironmentTests.cs','NativeLaunchEnvironmentPolicyTests.cs') | ForEach-Object { Join-Path $root $_ }
Add-Type -Path $sources
$a=[PortableVBox.NativePipeTransportTests].Assembly
$t=$a.GetType('PortableVBox.ChildCaptureOwner',$true)
$e=$a.GetType('PortableVBox.CaptureCase',$true)
$c=$t.GetConstructor([Reflection.BindingFlags]'Instance,NonPublic',$null,[type[]]@($e),$null)
$owner=$c.Invoke([object[]]@([Enum]::ToObject($e,0)))
$report=$a.GetType('PortableVBox.NativeLaunchEnvironmentNativeTests',$true).GetMethod('Report',[Reflection.BindingFlags]'Static,NonPublic')
Write-Output $report.Invoke($null,[object[]]@($owner,0,$false,$false,$false,$false))
""".replace('__ROOT__',str(ROOT/'tests/windows').replace("'","''"))
        result=subprocess.run([SHELL,'-NoProfile','-NonInteractive','-Command',script],capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        lines=result.stdout.splitlines();self.assertEqual(len(lines),1,result.stdout)
        report=strict_json(lines[0]);self.assertFalse(report['created']);self.assertEqual(report['create_calls'],0)
        summary=dict(kind='native_environment_summary',status='FAIL',cases=1,failed=1,
                     all_owners_released=False,sentinel_restored=False,mutation_authorized=False)
        with tempfile.TemporaryDirectory(prefix='pvbox-environment-serializer-') as root:
            path=Path(root)/'managed-only.jsonl'
            path.write_bytes((lines[0]+'\n'+json.dumps(summary)+'\n').encode('utf8'))
            self.assertEqual(validate_evidence(path),[report,summary])
            with self.assertRaises(ValueError): validate_evidence(path,True)

    def test_external_launch_and_receipt_inputs_rejected(self):
        for argument,value in (('-Executable','untrusted.exe'),('-ChildArguments','anything'),('-Environment','PATH=x'),('-ResumeEvidence','{}')):
            result=self.run_runner('-ManagedOnly',argument,value)
            with self.subTest(argument=argument):
                self.assertNotEqual(result.returncode,0)
                self.assertNotIn('managed environment integration PASS',result.stdout)

if __name__=='__main__':
    if len(sys.argv) in (3,4) and sys.argv[1]=='--validate-evidence':
        if len(sys.argv)==4 and sys.argv[3]!='--require-pass': raise SystemExit('Unsupported evidence option')
        result=validate_evidence(sys.argv[2],require_pass=len(sys.argv)==4)
        print('PASS strict bounded environment JSONL: %d observational records; no mutation authority' % len(result))
    else: unittest.main()
