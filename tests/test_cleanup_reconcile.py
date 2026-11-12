"""Real file-only observations; never a privileged cleanup or ownership permit."""
from pathlib import Path
import hashlib
import json
import os
import stat
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'scripts/reconcile_cleanup.py'
sys.path.insert(0,str(ROOT/'scripts'))

def sha(data): return hashlib.sha256(data).hexdigest()

class CleanupReconcile(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.exists(), 'Missing read-only cleanup reconciliation')
        import reconcile_cleanup
        self.mod=reconcile_cleanup
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name); self.session=self.root/'session'; self.session.mkdir()
        self.app=self.session/'app64'; self.app.mkdir()
        self.code=self.session/'code'; self.code.mkdir()
        self.files={'VirtualBox.exe':b'not executed','drivers/VBoxSup.inf':b'pinned driver info','nls/VirtualBox_ru.qm':b'ru'}
        rows=[]
        for name,data in self.files.items():
            target=self.app/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
            rows.append({'path':name,'size':len(data),'sha256':sha(data)})
        self.document={'file_count':len(rows),'total_bytes':sum(x['size'] for x in rows),'files':rows}
        self.manifest=self.root/'original.json';self.manifest.write_text(json.dumps(self.document))
        (self.app/'.prepared.json').write_text(json.dumps(self.document))
        canonical=''.join(x['path']+'\t'+str(x['size'])+'\t'+x['sha256']+'\n' for x in sorted(rows,key=lambda x:x['path']))
        self.pin={'file_count':len(rows),'total_bytes':self.document['total_bytes'],'manifest_rows_sha256':sha(canonical.encode())}
        self.source=self.root/'source.ps1';self.source.write_bytes(b'# not executed\n')
        (self.code/'worker.ps1').write_bytes(self.source.read_bytes())
        self.sources={'worker.ps1':self.source}
    def repin(self):
        rows=self.document['files']
        canonical=''.join(x['path']+'\t'+str(x['size'])+'\t'+x['sha256']+'\n' for x in sorted(rows,key=lambda x:x['path']))
        self.pin['manifest_rows_sha256']=sha(canonical.encode())
    def inspect(self): return self.mod.reconcile(self.session,self.manifest,self.pin,self.sources)
    def authority(self,result):
        self.assertIs(result['resume_authorized'],False)
        self.assertEqual(result['ownership'],'UNVERIFIED')
        self.assertEqual(result['system_state'],'NOT_OBSERVED')
    def test_intact_partial_and_absent_payload_are_only_observations(self):
        for removed,expected in [(0,'INTACT'),(1,'PARTIAL'),(3,'FILES_ABSENT')]:
            for name in list(self.files)[:removed]: (self.app/name).unlink(missing_ok=True)
            r=self.inspect();self.authority(r);self.assertEqual(r['status'],'REVIEW_ONLY');self.assertEqual(r['oracle_payload']['state'],expected)
            self.assertEqual(r['oracle_payload']['missing_count'],removed)
        (self.app/'.prepared.json').unlink()
        r=self.inspect();self.assertEqual(r['manifest_copy'],'ABSENT');self.authority(r)
    def test_cleanup_claim_cannot_verify_system_or_owner(self):
        (self.session/'cleanup').mkdir()
        (self.session/'cleanup/cleanup-results.json').write_text(json.dumps({'cleanup_verified':True,'driver_package_removed':True,'errors':[]}))
        (self.session/'payload-removed.json').write_text('{"protected_payload_removed":true}')
        r=self.inspect();self.authority(r);self.assertEqual(r['cleanup_receipt'],'CLAIMS_VERIFIED');self.assertEqual(r['payload_removed_marker'],'CLAIMS_REMOVED')
        self.assertEqual(r['status'],'BLOCKED') # marker contradicts still-present payload
    def test_deleted_trees_still_need_original_pin_and_never_authorize_replay(self):
        import shutil
        shutil.rmtree(self.app);shutil.rmtree(self.code)
        r=self.inspect();self.authority(r);self.assertEqual(r['status'],'REVIEW_ONLY')
        self.assertEqual(r['oracle_payload']['state'],'FILES_ABSENT');self.assertEqual(r['script_payload']['state'],'FILES_ABSENT')
        self.manifest.unlink();r=self.inspect();self.assertEqual(r['status'],'BLOCKED');self.authority(r)
    def test_modified_and_unexpected_payload_block_without_changes(self):
        target=self.app/'VirtualBox.exe';target.write_bytes(b'changed')
        before=target.read_bytes();r=self.inspect();self.assertEqual(r['status'],'BLOCKED');self.assertEqual(target.read_bytes(),before)
        target.write_bytes(self.files['VirtualBox.exe']);(self.app/'extra.dll').write_bytes(b'extra')
        self.assertEqual(self.inspect()['status'],'BLOCKED')
    def test_unexpected_directory_or_wrong_script_blocks(self):
        (self.code/'unknown').mkdir();self.assertEqual(self.inspect()['status'],'BLOCKED');(self.code/'unknown').rmdir()
        (self.code/'worker.ps1').write_bytes(b'wrong');self.assertEqual(self.inspect()['status'],'BLOCKED')
    def test_manifest_digest_and_duplicate_keys_are_fail_closed(self):
        self.document['files'][0]['sha256']='0'*64
        self.manifest.write_text(json.dumps(self.document));self.assertEqual(self.inspect()['status'],'BLOCKED')
        self.manifest.write_text('{"files":[],"files":[]}');self.assertEqual(self.inspect()['status'],'BLOCKED')
    def test_unsafe_or_case_colliding_manifest_names_refused(self):
        for name in ['../outside','C:/Windows/a','a:stream','CON','a.','a//b','a\\b']:
            self.document['files'][0]['path']=name;self.repin();self.manifest.write_text(json.dumps(self.document))
            self.assertEqual(self.inspect()['status'],'BLOCKED',name)
        self.document['files'][0]['path']='drivers/vboxsup.INF';self.repin();self.manifest.write_text(json.dumps(self.document));self.assertEqual(self.inspect()['status'],'BLOCKED')
    def test_hardlink_refused(self):
        target=self.app/'VirtualBox.exe';target.unlink()
        other=self.root/'outside';other.write_bytes(self.files['VirtualBox.exe']);os.link(other,target)
        self.assertEqual(self.inspect()['status'],'BLOCKED');self.assertEqual(other.read_bytes(),self.files['VirtualBox.exe'])
    def test_symlink_root_file_and_missing_root_refused(self):
        target=self.app/'VirtualBox.exe';target.unlink();other=self.root/'outside';other.write_bytes(b'do not inspect')
        try: target.symlink_to(other)
        except OSError: self.skipTest('symlink creation unavailable')
        self.assertEqual(self.inspect()['status'],'BLOCKED');target.unlink();target.write_bytes(self.files['VirtualBox.exe'])
        link=self.root/'linked';link.symlink_to(self.session,target_is_directory=True)
        r=self.mod.reconcile(link,self.manifest,self.pin,self.sources);self.assertEqual(r['status'],'BLOCKED')
        self.assertEqual(self.mod.reconcile(self.root/'missing',self.manifest,self.pin,self.sources)['status'],'BLOCKED')
    def test_json_claims_must_have_real_booleans_and_no_duplicate_keys(self):
        (self.session/'cleanup').mkdir();claim=self.session/'cleanup/cleanup-results.json'
        for data in ['{"cleanup_verified":"true","driver_package_removed":true,"errors":[]}', '{"cleanup_verified":true,"cleanup_verified":false}']:
            claim.write_text(data);self.assertEqual(self.inspect()['status'],'BLOCKED')
    def test_second_observation_detects_changed_files(self):
        real=self.mod._snapshot; calls=0
        def change(*args,**kwargs):
            nonlocal calls
            out=real(*args,**kwargs);calls+=1
            if calls==1: (self.app/'VirtualBox.exe').write_bytes(b'changed')
            return out
        with patch.object(self.mod,'_snapshot',side_effect=change): r=self.inspect()
        self.assertEqual(r['status'],'BLOCKED');self.authority(r)
    def test_changed_receipt_bytes_are_not_hidden_by_same_claim_class(self):
        (self.session/'cleanup').mkdir();claim=self.session/'cleanup/cleanup-results.json'
        claim.write_text(json.dumps({'cleanup_verified':False,'driver_package_removed':False,'errors':['first']}))
        real=self.mod._snapshot; calls=0
        def change(*args,**kwargs):
            nonlocal calls
            out=real(*args,**kwargs);calls+=1
            if calls==1: claim.write_text(json.dumps({'cleanup_verified':False,'driver_package_removed':False,'errors':['second']}))
            return out
        with patch.object(self.mod,'_snapshot',side_effect=change): r=self.inspect()
        self.assertEqual(r['status'],'BLOCKED')
    def test_inaccessible_or_oversized_input_fails_closed(self):
        real=self.mod._read_file
        def deny(path,**kwargs):
            if Path(path)==self.app/'VirtualBox.exe': raise PermissionError('private path must not be printed')
            return real(path,**kwargs)
        with patch.object(self.mod,'_read_file',side_effect=deny):
            result=self.inspect();self.assertEqual(result['errors'],['READ_UNAVAILABLE'])
        self.manifest.write_bytes(b' '*131073);self.assertEqual(self.inspect()['status'],'BLOCKED')

    @unittest.skipUnless(hasattr(os,'O_NONBLOCK'),'POSIX nonblocking open flag')
    def test_changed_opened_file_type_is_nonblocking_and_never_read(self):
        actual_open=self.mod.os.open; actual_fdopen=self.mod.os.fdopen; actual_fstat=self.mod.os.fstat
        flags_seen=[]
        def open_record(path,flags,*args):
            flags_seen.append(flags)
            return actual_open(path,flags,*args)
        def changed_type(fd):
            fields=list(actual_fstat(fd));fields[0]=stat.S_IFIFO|0o600
            return os.stat_result(fields)
        class NoRead:
            def __init__(inner,stream): inner.stream=stream
            def __enter__(inner): return inner
            def __exit__(inner,*args): inner.stream.close()
            def fileno(inner): return inner.stream.fileno()
            def read(inner,*args): self.fail('Reading began before opened file type was verified')
        with patch.object(self.mod.os,'open',side_effect=open_record), patch.object(self.mod.os,'fstat',side_effect=changed_type), patch.object(self.mod.os,'fdopen',side_effect=lambda *a:NoRead(actual_fdopen(*a))):
            with self.assertRaises(self.mod.ObservationError): self.mod._read_file(self.app/'VirtualBox.exe')
        self.assertTrue(flags_seen and all(f&os.O_NONBLOCK for f in flags_seen))

    def test_directory_enumeration_stops_at_bound_before_materializing_all_entries(self):
        real=self.mod.os.scandir; consumed=0
        class ManyEntries:
            def __enter__(inner):
                with real(self.app) as found: first=next(found)
                def entries():
                    nonlocal consumed
                    for _ in range(self.mod.MAX_ENTRIES+100):
                        consumed+=1
                        yield first
                return entries()
            def __exit__(inner,*args): pass
        with patch.object(self.mod.os,'scandir',return_value=ManyEntries()): r=self.inspect()
        self.assertEqual(r['status'],'BLOCKED')
        self.assertLessEqual(consumed,self.mod.MAX_ENTRIES+1)

    def test_windows_cached_direntry_zero_link_count_is_not_identity_evidence(self):
        real=self.mod.os.scandir
        class CachedEntry:
            def __init__(inner,entry): inner.name=entry.name;inner.path=entry.path
            def stat(inner,**kwargs):
                fields=list(Path(inner.path).lstat())
                fields[1]=fields[2]=fields[3]=0 # Windows DirEntry omits ino/dev/nlink.
                return os.stat_result(fields)
        class CachedScan:
            def __init__(inner,path): inner.iterator=real(path)
            def __enter__(inner): return (CachedEntry(x) for x in inner.iterator)
            def __exit__(inner,*args): inner.iterator.close()
        with patch.object(self.mod.os,'scandir',side_effect=CachedScan): result=self.inspect()
        self.assertEqual(result['status'],'REVIEW_ONLY',result)
        self.authority(result)

    def test_windows_filename_execute_bits_and_ctime_mapping_do_not_change_identity(self):
        checked=self.mod._checked_path;fstat=self.mod.os.fstat
        def copy_stat(info):
            return SimpleNamespace(**{key:getattr(info,key) for key in dir(info) if key.startswith('st_')})
        def path_stat(*args,**kwargs):
            info=copy_stat(checked(*args,**kwargs))
            info.st_birthtime_ns=123456789
            info.st_mode|=0o111 # CPython path-stat marks executable extensions.
            return info
        def opened_stat(fd):
            info=copy_stat(fstat(fd));info.st_birthtime_ns=123456789
            info.st_mode&=~0o111;info.st_ctime_ns+=1000
            return info
        with patch.object(self.mod,'WINDOWS',True,create=True), patch.object(self.mod,'_checked_path',side_effect=path_stat), patch.object(self.mod.os,'fstat',side_effect=opened_stat):
            digest,_=self.mod._read_file(self.app/'VirtualBox.exe')
        self.assertEqual(digest,sha(self.files['VirtualBox.exe']))

    def test_windows_cross_method_normalization_keeps_real_identity_strict(self):
        fstat=self.mod.os.fstat
        for field in ('st_dev','st_ino','st_size','st_mtime_ns','st_nlink','st_file_attributes','st_birthtime_ns','st_mode'):
            with self.subTest(field=field):
                def changed(fd):
                    info=fstat(fd)
                    data={key:getattr(info,key) for key in dir(info) if key.startswith('st_')}
                    value=data.get(field,0)
                    data[field]=(value^0o200) if field=='st_mode' else value+1
                    return SimpleNamespace(**data)
                with patch.object(self.mod,'WINDOWS',True), patch.object(self.mod.os,'fstat',side_effect=changed):
                    with self.assertRaises(self.mod.ObservationError): self.mod._read_file(self.app/'VirtualBox.exe')

    def test_windows_birthtime_missing_on_one_side_is_not_silently_ignored(self):
        info=(self.app/'VirtualBox.exe').stat()
        original={key:getattr(info,key) for key in dir(info) if key.startswith('st_')}
        original.pop('st_birthtime_ns',None)
        with_birth=dict(original,st_birthtime_ns=info.st_ctime_ns)
        with patch.object(self.mod,'WINDOWS',True):
            self.assertNotEqual(self.mod._opening_stamp(SimpleNamespace(**original)),self.mod._opening_stamp(SimpleNamespace(**with_birth)))

    def test_windows_same_method_ctime_change_during_read_still_blocks(self):
        fstat=self.mod.os.fstat;calls=0
        def changing(fd):
            nonlocal calls
            info=fstat(fd);calls+=1
            data={key:getattr(info,key) for key in dir(info) if key.startswith('st_')}
            if calls>1: data['st_ctime_ns']+=1
            return SimpleNamespace(**data)
        with patch.object(self.mod,'WINDOWS',True), patch.object(self.mod.os,'fstat',side_effect=changing):
            with self.assertRaises(self.mod.ObservationError): self.mod._read_file(self.app/'VirtualBox.exe')

    def test_observation_opens_only_read_handles_and_preserves_bytes(self):
        before={str(p.relative_to(self.root)):p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        original=self.mod.os.open
        def readonly(path,flags,*args,**kwargs):
            self.assertFalse(flags & (os.O_WRONLY|os.O_RDWR|os.O_CREAT|os.O_TRUNC|os.O_APPEND))
            return original(path,flags,*args,**kwargs)
        with patch.object(self.mod.os,'open',side_effect=readonly): result=self.inspect()
        self.assertEqual(result['status'],'REVIEW_ONLY')
        after={str(p.relative_to(self.root)):p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        self.assertEqual(before,after)
    def test_embedded_bridge_without_binary_provenance_remains_blocked(self):
        bridge=self.code/'PortableVBox.SdsBridge.dll'
        bridge.write_bytes(b'unknown compiled bridge')
        before={str(p.relative_to(self.root)):p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        result=self.inspect()
        self.assertEqual(result['status'],'BLOCKED')
        self.authority(result)
        self.assertEqual(before,{str(p.relative_to(self.root)):p.read_bytes() for p in self.root.rglob('*') if p.is_file()})

    def test_inventory_is_the_existing_fixed_helper_script_allowlist(self):
        import re
        text=(ROOT/'source/privilege/SessionHelper.cs').read_text()
        block=text.split('static readonly string[] Scripts={',1)[1].split('};',1)[0]
        self.assertEqual(tuple(re.findall(r'"([^"\n]+)"',block)),self.mod.SCRIPT_NAMES+('PortableVBox.SdsBridge.dll',))
        self.assertNotIn('reconcile_cleanup.py',(ROOT/'scripts/package_preview.py').read_text())
        self.assertNotIn('reconcile_cleanup.py',(ROOT/'scripts/build_session_helper.ps1').read_text())

    def test_cli_invalid_manifest_returns_bounded_non_authoritative_json(self):
        result=subprocess.run([sys.executable,str(SCRIPT),str(self.session),'--manifest',str(self.manifest)],text=True,capture_output=True)
        self.assertEqual(result.returncode,3);r=json.loads(result.stdout);self.assertEqual(r['status'],'BLOCKED');self.authority(r)
        self.assertNotIn(str(self.root),result.stdout)

if __name__=='__main__': unittest.main()
