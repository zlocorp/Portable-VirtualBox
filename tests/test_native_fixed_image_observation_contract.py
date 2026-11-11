"""Independent fixed-image file-only diagnostics; never mutation authority."""
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHELL = os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh')
CASES = ('matching-image', 'digest-mismatch', 'size-mismatch', 'missing-image')
MAX_IMAGE = 16 * 1024 * 1024

@unittest.skipUnless(SHELL, 'PowerShell compiler required')
class FixedImageManagedContracts(unittest.TestCase):
    def test_behavioral_contracts(self):
        result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-File',
            str(ROOT/'tests/windows/check_native_fixed_image_observation.ps1'), '-ManagedOnly'],
            capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn('PASS fixed image managed contracts', result.stdout)
        self.assertTrue((ROOT/'tests/windows/check_native_fixed_image_observation.ps1').read_text(encoding='utf-8').isascii(),
                        'Windows PowerShell 5.1 runner must remain encoding-safe ASCII source')
        retained=re.search(r'Generated fixed image build/evidence retained at (.+?)\. Process teardown',result.stdout)
        self.assertIsNotNone(retained)
        build=Path(retained.group(1));pristine=(build/'pristine/NativeCaptureFixtureChild.exe').read_bytes()
        generated=(build/'FixedFixtureBuildExpectation.g.cs').read_bytes()
        self.assertLessEqual(len(generated),2048)
        exact=('// Generated from completed pristine harmless build bytes. TEST ONLY.\n'
               'namespace PortableVBox { internal static class FixedFixtureBuildExpectation { '
               'internal const string Name = "NativeCaptureFixtureChild.exe"; internal const long Length = '
               +str(len(pristine))+'L; internal const string Sha256 = "'+hashlib.sha256(pristine).hexdigest()+'"; } }\n')
        self.assertEqual(generated,exact.encode('utf-8'))
        for name in CASES:
            directory=build/'fixed-Ж-漢'/name
            self.assertTrue((directory/'NativeFixedImageIdentityTests.exe').is_file())
            self.assertEqual((directory/'FixedFixtureCase.g.cs').read_text(),
                'namespace PortableVBox { internal static class FixedFixtureCase { internal const string Name = "'+name+'"; } }')
            self.assertFalse((directory/'NativeCaptureFixtureChild.exe').exists(),'Managed-only must never prepare or execute negative child copies')
        unicode_lines=[line.split(' ',1)[1] for line in result.stdout.splitlines()
                       if line.startswith('SERIALIZER_UNICODE ')]
        self.assertEqual(len(unicode_lines),1)
        wire=unicode_lines[0]
        self.assertTrue(wire.isascii(),'Every JSON UTF16 unit outside ASCII must be escaped')
        transported=wire.encode('cp437',errors='replace').decode('cp437')
        self.assertEqual(transported,wire,'Console transport must not substitute actual path units')
        unicode_record=json.loads(transported)
        self.assertEqual(unicode_record['held_path'],'C:\\Привет\\漢字-é-🙂\\NativeCaptureFixtureChild.exe')
        complete=samples();complete[0]=unicode_record
        self.assertTrue(validate_records(complete,True))
        probe_lines=[json.loads(line.split(' ',1)[1]) for line in result.stdout.splitlines()
                     if line.startswith('PROBE_DIAGNOSTIC ')]
        self.assertEqual(len(probe_lines),3)
        for record,open_state,close_state in zip(probe_lines,
                ('return-unknown','returned-success','returned-success'),
                ('not-opened','return-unknown','returned-failure')):
            self.assertEqual(record['write_probe']['open_state'],open_state)
            self.assertEqual(record['write_probe']['close_state'],close_state)
            self.assertIsNone(record['write_probe']['open_error'])
            self.assertEqual(record['close_state'],'not-entered','Unresolved probe must retain image owner')
            diagnostics=[record,summary(1,1,'unresolved-owner')]
            self.assertFalse(validate_records(diagnostics))
            with self.assertRaises(ValueError): validate_records(diagnostics,True)
            with self.assertRaises(ValueError):
                validate_records([record]+samples()[1:-1]+[summary(4,1,'case-failure')])
        serialized=[json.loads(line.split(' ',1)[1]) for line in result.stdout.splitlines()
                    if line.startswith('SERIALIZER_DIAGNOSTIC ')]
        self.assertEqual(len(serialized),3)
        for record in serialized:
            self.assertIsNone(record['read_error']);self.assertIsNone(record['actual_sha256'])
            self.assertEqual(record['read_state'],'known-incomplete')
            self.assertFalse(validate_records([record,summary(1,1,'case-failure')]))
            record['status']='PASS'
            with self.assertRaises(ValueError): validate_records([record,summary(1,0,'case-failure')])

class FixedImageArtifactContracts(unittest.TestCase):
    def test_accept_complete_independent_fixture(self):
        self.assertTrue(validate_records(samples(), require_pass=True))

    def test_composed_stage_not_available_in_task1(self):
        records=samples()
        for record in records: record['stage']='composed'
        with self.assertRaises(ValueError): validate_records(records)

    def test_mutations(self):
        changes = [('mutation_authorized', True), ('hash_matches', True),
            ('actual_sha256', ''), ('actual_size', None), ('bytes_hashed', 0),
            ('eof_request_bytes', 0), ('eof_request_bytes', 2), ('eof_return_bytes', 1), ('volume_serial', ''),
            ('held_path', ''), ('create_calls', 1), ('process_observation', {}),
            ('read_state', 'known-incomplete'), ('read_error', 5), ('close_state', 'returned-failure')]
        for key, value in changes:
            with self.subTest(key=key):
                records=samples();records[0][key]=value
                with self.assertRaises(ValueError): validate_records(records, True)

    def test_failure_prefix_is_diagnostic_only(self):
        records=samples()[:1];records[0].update(status='FAIL', refusal='observation-failure', close_state='return-unknown')
        records.append(summary(1, 1, 'unresolved-owner'))
        self.assertFalse(validate_records(records))
        with self.assertRaises(ValueError): validate_records(records, True)

    def test_known_incomplete_diagnostics(self):
        for request, returned, hashed in [(65536,0,1),(1,1,17),(None,None,1)]:
            records=samples()[:1];records[0].update(status='FAIL', refusal='observation-failure',
                read_state='known-incomplete', actual_sha256=None, read_error=None,
                eof_request_bytes=request,eof_return_bytes=returned,bytes_hashed=hashed,write_probe=None,delete_probe=None)
            records.append(summary(1,1,'case-failure'))
            self.assertFalse(validate_records(records))
            records[0]['status']='PASS'
            with self.assertRaises(ValueError): validate_records(records)

    def test_native_unknown_and_known_failure_diagnostics(self):
        unknown=samples()[3];unknown.update(case='matching-image',status='FAIL',refusal='observation-failure',
            open_state='return-unknown',open_error=None)
        self.assertFalse(validate_records([unknown,summary(1,1,'unresolved-owner')]))
        unknown['close_state']='returned-success'
        with self.assertRaises(ValueError): validate_records([unknown,summary(1,1,'unresolved-owner')])
        for state,error,close,reason in [('return-unknown',None,'not-entered','unresolved-owner'),
                                         ('returned-failure',5,'returned-success','case-failure')]:
            record=samples()[0];record.update(status='FAIL',refusal='observation-failure',read_state=state,
                read_error=error,actual_sha256=None,bytes_hashed=3,eof_request_bytes=None,eof_return_bytes=None,
                write_probe=None,delete_probe=None,close_state=close)
            self.assertFalse(validate_records([record,summary(1,1,reason)]))

    def test_forged_pass_prefix_is_not_acceptance(self):
        for count in range(4):
            with self.assertRaises(ValueError): validate_records(samples()[:count]+[summary(count,0)],True)

    def test_sequence_and_summary_mutations_independent(self):
        for records in [samples()[:1]+samples(), [samples()[1],samples()[0]]+samples()[2:],
                        samples()+[samples()[-1]], samples()[:-1], samples()[1:]]:
            with self.assertRaises(ValueError): validate_records(records)
        for key,value in [('cases',3),('failed',1),('stop_reason','case-failure'),('schema',True)]:
            records=samples();records[-1][key]=value
            with self.assertRaises(ValueError): validate_records(records)

    def test_probe_contract_and_native_result_consistency(self):
        for key,value in [('share',1),('disposition',2),('access','DELETE'),('open_error',0),
                          ('open_state','returned-success'),('close_state','returned-success')]:
            records=samples();records[0]['write_probe'][key]=value
            with self.assertRaises(ValueError): validate_records(records)
        for index,key,value in [(3,'open_error',3),(3,'actual_size',0),(2,'read_state','complete'),
                                (1,'actual_sha256','a'*64),(0,'open_error',0)]:
            records=samples();records[index][key]=value
            with self.assertRaises(ValueError): validate_records(records)

    def test_unresolved_owner_must_stop_later_cases(self):
        for state in ('return-unknown','returned-failure','not-entered'):
            records=samples();records[0].update(status='FAIL',close_state=state)
            records[-1]=summary(4,1,'case-failure')
            with self.assertRaises(ValueError): validate_records(records)
        records=samples()[:1];records[0].update(status='FAIL',close_state='return-unknown')
        records.append(summary(1,1,'case-failure'))
        with self.assertRaises(ValueError): validate_records(records)

    def test_nullability_types_and_stale_expectation(self):
        for key,value in [('schema',True),('expected_size',True),('bytes_hashed',1.0),
                          ('open_state',''),('read_state',''),('actual_sha256','A'*64),
                          ('held_path','C:\\bad\ud800'),('held_path','C:\\bad\0path'),
                          ('held_path','\\\\server\\file'),('eof_request_bytes',False),
                          ('file_id',None),('volume_serial',True)]:
            records=samples();records[0][key]=value
            with self.assertRaises(ValueError): validate_records(records)
        records=samples();records[1]['expected_sha256']='c'*64
        with self.assertRaises(ValueError): validate_records(records)
        self.assertFalse(validate_records([summary(0,0,'build-failure')]))
        with self.assertRaises(ValueError): validate_records([summary(0,0,'build-failure')],True)

    def test_utf8_bounds_duplicates_and_truncation(self):
        raw=''.join(json.dumps(r)+'\n' for r in samples()).encode()
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'evidence'
            path.write_bytes(raw);self.assertTrue(validate_evidence(path,True))
            for bad in [raw[:-1],raw.replace(b'"schema": 1',b'"schema": 1,"schema":1',1),
                        b' '*16384+b'\n',b'\xff\n',raw+b'{}\n',raw[:-20],b'\n',b'x'*131073]:
                path.write_bytes(bad)
                with self.assertRaises(ValueError): validate_evidence(path)


CASE_FIELDS=frozenset(('kind','schema','stage','case','status','mutation_authorized','refusal',
    'create_calls','expected_size','expected_sha256','open_state','open_error','actual_size',
    'actual_sha256','bytes_hashed','read_state','read_error','eof_request_bytes','eof_return_bytes',
    'volume_serial','file_id','held_path','write_probe','delete_probe','close_state','process_observation'))
SUMMARY_FIELDS=frozenset(('kind','schema','stage','status','cases','failed','stop_reason','mutation_authorized'))
PROBE_FIELDS=frozenset(('access','share','disposition','open_state','open_error','close_state'))
OPEN_STATES=('not-entered','return-unknown','returned-failure','returned-success')
CLOSE_STATES=('not-opened','not-entered','return-unknown','returned-failure','returned-success')
READ_STATES=('not-entered','return-unknown','returned-failure','known-incomplete','complete')


def summary(cases=4,failed=0,reason='none',stage='file-only'):
    return dict(kind='fixed_image_summary',schema=1,stage=stage,status='PASS' if reason=='none' else 'FAIL',
                cases=cases,failed=failed,stop_reason=reason,mutation_authorized=False)


def samples():
    """Independent synthetic fixtures, never evidence of Windows execution."""
    records=[]
    for index,name in enumerate(CASES):
        record=dict(kind='fixed_image_case',schema=1,stage='file-only',case=name,status='PASS',
            mutation_authorized=False,refusal=('none','digest-mismatch','size-mismatch','missing-image')[index],
            create_calls=0,expected_size=17,expected_sha256='a'*64,open_state='returned-success',open_error=None,
            actual_size=17,actual_sha256='a'*64,bytes_hashed=17,read_state='complete',read_error=None,
            eof_request_bytes=1,eof_return_bytes=0,volume_serial='0000000000000000',file_id='01'*16,
            held_path='\\\\?\\C:\\fixed\\NativeCaptureFixtureChild.exe',write_probe=None,delete_probe=None,
            close_state='returned-success',process_observation=None)
        if index==0:
            for key,access in [('write_probe','GENERIC_WRITE'),('delete_probe','DELETE')]:
                record[key]=dict(access=access,share=7,disposition=3,open_state='returned-failure',open_error=32,close_state='not-opened')
        if index==1: record['actual_sha256']='b'*64
        if index>=2:
            record.update(actual_size=18 if index==2 else None,actual_sha256=None,bytes_hashed=0,
                read_state='not-entered',eof_request_bytes=None,eof_return_bytes=None,volume_serial=None,file_id=None,held_path=None)
        if index==3: record.update(open_state='returned-failure',open_error=2,close_state='not-opened')
        records.append(record)
    return records+[summary()]


def integer(value, maximum, minimum=0):
    if type(value) is not int or not minimum<=value<=maximum: raise ValueError('Invalid bounded integer')


def hex_value(value,length,nullable=False):
    if nullable and value is None: return
    if type(value) is not str or re.fullmatch('[0-9a-f]{'+str(length)+'}',value) is None:
        raise ValueError('Invalid exact lowercase hex observation')


def strings(value):
    if type(value) is str:
        if '\0' in value: raise ValueError('NUL in evidence string')
        try: value.encode('utf-16-le',errors='strict')
        except UnicodeEncodeError as error: raise ValueError('Invalid UTF16 string') from error
    elif type(value) is dict:
        for key,item in value.items(): strings(key);strings(item)
    elif type(value) is list:
        for item in value: strings(item)


def local_path(value):
    if type(value) is not str or not value or len(value.encode('utf-16-le'))//2>=32768:
        raise ValueError('Missing/bounded local DOS path')
    strings(value)
    plain=value[4:] if value.startswith('\\\\?\\') else value
    if re.match(r'\A[A-Za-z]:\\',plain) is None or any(ord(c)<32 or c=='\x7f' for c in plain):
        raise ValueError('Unsupported non-local-DOS path')
    return plain


def native_open(record):
    if record['open_state'] not in OPEN_STATES: raise ValueError('Unknown open state')
    if record['close_state'] not in CLOSE_STATES: raise ValueError('Unknown close state')
    if record['open_state']=='returned-failure': integer(record['open_error'],4294967295)
    elif record['open_error'] is not None: raise ValueError('Unavailable open error must be null')
    if record['open_state']!='returned-success' and record['close_state']!='not-opened':
        raise ValueError('Cannot close unowned/unknown handle')
    if record['open_state']=='returned-success' and record['close_state']=='not-opened':
        raise ValueError('Successful open owns exact handle')


def probe(value,access):
    if value is None: return
    if type(value) is not dict or set(value)!=PROBE_FIELDS: raise ValueError('Probe fields')
    if value['access']!=access or type(value['share']) is not int or value['share']!=7 or type(value['disposition']) is not int or value['disposition']!=3:
        raise ValueError('Probe exact compatible sharing/access/disposition')
    native_open(value)


def validate_case(record):
    if type(record) is not dict or set(record)!=CASE_FIELDS: raise ValueError('Unexpected exact case fields')
    strings(record)
    if record['kind']!='fixed_image_case' or type(record['schema']) is not int or record['schema']!=1: raise ValueError('Case version')
    if record['stage']!='file-only' or record['case'] not in CASES or record['status'] not in ('PASS','FAIL'):
        raise ValueError('Case labels')
    if record['mutation_authorized'] is not False: raise ValueError('Observations never authorize mutation')
    if record['refusal'] not in ('none','digest-mismatch','size-mismatch','missing-image','observation-failure'): raise ValueError('Refusal label')
    integer(record['expected_size'],MAX_IMAGE,1);hex_value(record['expected_sha256'],64)
    integer(record['create_calls'],2147483647);integer(record['bytes_hashed'],MAX_IMAGE)
    if record['bytes_hashed']>record['expected_size']: raise ValueError('Hashed bytes exceed expectation')
    if record['actual_size'] is not None:
        integer(record['actual_size'],9223372036854775807)
        if record['bytes_hashed']>record['actual_size']: raise ValueError('Hashed bytes exceed held size')
    hex_value(record['actual_sha256'],64,True);hex_value(record['volume_serial'],16,True);hex_value(record['file_id'],32,True)
    if (record['volume_serial'] is None)!=(record['file_id'] is None): raise ValueError('Identity query is atomic')
    if record['held_path'] is not None: local_path(record['held_path'])
    native_open(record)
    if record['read_state'] not in READ_STATES: raise ValueError('Read state')
    if record['read_state']=='returned-failure': integer(record['read_error'],4294967295)
    elif record['read_error'] is not None: raise ValueError('Unavailable read error must be null')
    if (record['eof_request_bytes'] is None)!=(record['eof_return_bytes'] is None): raise ValueError('Terminal read pair')
    if record['eof_request_bytes'] is not None:
        integer(record['eof_request_bytes'],65536,1);integer(record['eof_return_bytes'],4294967295)
        if record['read_state'] not in ('complete','known-incomplete'): raise ValueError('Only successful terminal read has counts')
    if record['open_state']!='returned-success':
        if any(record[key] is not None for key in ('actual_size','actual_sha256','volume_serial','file_id','held_path','write_probe','delete_probe')) or record['read_state']!='not-entered' or record['bytes_hashed']!=0:
            raise ValueError('No observations without known successful open')
    if record['read_state']=='not-entered':
        if record['bytes_hashed']!=0 or record['actual_sha256'] is not None or record['eof_request_bytes'] is not None: raise ValueError('Read not entered observations unavailable')
    else:
        if record['actual_size']!=record['expected_size'] or record['volume_serial'] is None or record['held_path'] is None:
            raise ValueError('Read requires size, identity and path preflight')
    if record['read_state']=='return-unknown' and record['close_state']!='not-entered': raise ValueError('Unknown read forbids close reuse')
    if record['read_state']=='complete':
        if record['actual_sha256'] is None or record['bytes_hashed']!=record['expected_size'] or record['eof_request_bytes']!=1 or record['eof_return_bytes']!=0:
            raise ValueError('Complete requires full digest and positive one-byte EOF proof')
    elif record['actual_sha256'] is not None: raise ValueError('Incomplete read has no actual image digest')
    probe(record['write_probe'],'GENERIC_WRITE');probe(record['delete_probe'],'DELETE')
    if record['case']!='matching-image' and (record['write_probe'] is not None or record['delete_probe'] is not None): raise ValueError('Probes confined to matching case')
    if any(record[key] is not None for key in ('write_probe','delete_probe')):
        if record['read_state']!='complete' or record['actual_sha256']!=record['expected_sha256']: raise ValueError('Probes require complete matching image')
    if record['refusal']=='none' and (record['read_state']!='complete' or record['actual_sha256']!=record['expected_sha256']): raise ValueError('No refusal requires observed digest match')
    if record['refusal']=='digest-mismatch' and (record['read_state']!='complete' or record['actual_sha256']==record['expected_sha256']): raise ValueError('Digest refusal requires comparison reached')
    if record['refusal']=='size-mismatch' and (record['actual_size'] is None or record['actual_size']==record['expected_size'] or record['read_state']!='not-entered'): raise ValueError('Size refusal differs from digest refusal')
    if record['refusal']=='missing-image' and (record['open_state']!='returned-failure' or record['open_error']!=2): raise ValueError('Missing sibling requires actual error 2')
    if record['create_calls']!=0 or record['process_observation'] is not None: raise ValueError('Task 1 has no create/query')
    if record['status']=='PASS':
        name=record['case']
        if record['read_state']=='known-incomplete': raise ValueError('Incomplete never PASS')
        if record['refusal']!=('none','digest-mismatch','size-mismatch','missing-image')[CASES.index(name)]: raise ValueError('Wrong expected refusal')
        if name!='missing-image' and (record['open_state']!='returned-success' or record['close_state']!='returned-success'): raise ValueError('PASS requires checked image release')
        if name in ('matching-image','digest-mismatch'):
            if record['read_state']!='complete' or record['volume_serial'] is None or record['file_id'] is None or record['held_path'] is None: raise ValueError('PASS requires actual complete held-file observation')
        if name=='matching-image':
            for key in ('write_probe','delete_probe'):
                value=record[key]
                if value is None or value['open_state']!='returned-failure' or value['open_error']!=32 or value['close_state']!='not-opened': raise ValueError('PASS requires actual sharing denial')


def unresolved_owner(record):
    unresolved=record['open_state']=='return-unknown' or (record['open_state']=='returned-success' and record['close_state']!='returned-success')
    for key in ('write_probe','delete_probe'):
        value=record[key]
        if value is not None:
            unresolved=unresolved or value['open_state']=='return-unknown' or (value['open_state']=='returned-success' and value['close_state']!='returned-success')
    return unresolved


def validate_records(records,require_pass=False):
    if not 1<=len(records)<=5: raise ValueError('At most four cases and summary')
    cases=records[:-1];end=records[-1]
    if type(end) is not dict or set(end)!=SUMMARY_FIELDS: raise ValueError('Missing exact final summary')
    strings(end)
    if end['kind']!='fixed_image_summary' or type(end['schema']) is not int or end['schema']!=1 or end['stage']!='file-only' or end['status'] not in ('PASS','FAIL') or end['mutation_authorized'] is not False: raise ValueError('Summary labels/version')
    integer(end['cases'],4);integer(end['failed'],4)
    if end['stop_reason'] not in ('none','case-failure','unresolved-owner','build-failure','evidence-failure'): raise ValueError('Summary stop reason')
    expected=None
    for index,record in enumerate(cases):
        validate_case(record)
        if record['case']!=CASES[index] or record['stage']!=end['stage']: raise ValueError('Ordered case prefix/stage')
        value=(record['expected_size'],record['expected_sha256'])
        if expected is not None and value!=expected: raise ValueError('Cases must retain same pristine build expectation')
        expected=value
        if unresolved_owner(record) and (index!=len(cases)-1 or end['stop_reason']!='unresolved-owner'):
            raise ValueError('Unresolved owner must stop later cases with retained diagnostics')
    if end['cases']!=len(cases) or end['failed']!=sum(r['status']=='FAIL' for r in cases): raise ValueError('Summary count mismatch')
    passed=end['status']=='PASS'
    if passed:
        if len(cases)!=4 or end['failed']!=0 or end['stop_reason']!='none': raise ValueError('PASS requires all four ordered PASS cases')
    elif end['stop_reason']=='none': raise ValueError('FAIL requires stop reason')
    if end['stop_reason']=='build-failure' and cases: raise ValueError('Build failure precedes native cases')
    if end['stop_reason']=='case-failure' and (not cases or end['failed']==0): raise ValueError('Case failure requires actual failed case')
    if end['stop_reason']=='unresolved-owner':
        if not cases or cases[-1]['status']!='FAIL': raise ValueError('Unresolved owner requires attempted failed case')
        if not unresolved_owner(cases[-1]): raise ValueError('Unresolved-owner stop requires retained native ownership')
    if require_pass and not passed: raise ValueError('Diagnostics are not acceptance')
    return passed


def strict_json(line):
    def pairs(items):
        result={}
        for key,value in items:
            if key in result: raise ValueError('Duplicate JSON key')
            result[key]=value
        return result
    def invalid(value): raise ValueError('Nonfinite JSON value')
    try: return json.loads(line,object_pairs_hook=pairs,parse_constant=invalid)
    except (RecursionError,json.JSONDecodeError) as error: raise ValueError('Invalid bounded JSON') from error


def validate_evidence(path,require_pass=False):
    path=Path(path)
    if not 0<path.stat().st_size<=131072: raise ValueError('Artifact total bound')
    records=[];total=0
    with path.open('rb') as stream:
        while True:
            line=stream.readline(16385)
            if not line: break
            total+=len(line)
            if len(line)>16384 or total>131072 or len(records)>=5 or not line.endswith(b'\n'): raise ValueError('Record bound/truncation')
            try: value=strict_json(line.decode('utf-8',errors='strict'))
            except UnicodeDecodeError as error: raise ValueError('Invalid UTF8 evidence') from error
            records.append(value)
    return validate_records(records,require_pass)


if __name__=='__main__':
    if '--validate-evidence' in sys.argv:
        import argparse
        parser=argparse.ArgumentParser(description='Validate fixed-image diagnostics only, never resource authority')
        parser.add_argument('--validate-evidence',required=True);parser.add_argument('--require-pass',action='store_true')
        args=parser.parse_args()
        try:
            passed=validate_evidence(args.validate_evidence,args.require_pass)
            print('PASS fixed image evidence schema'+(' and all cases' if passed else ' (FAIL diagnostics only)'))
        except (OSError,ValueError) as error:
            print('Invalid fixed image evidence: '+str(error),file=sys.stderr);sys.exit(1)
    else: unittest.main()
