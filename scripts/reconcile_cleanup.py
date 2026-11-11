"""Read-only partial-cleanup file reconciliation. NEVER a replay/deletion permit.

No privileged helper entrypoint, system query, executable launch or write is used.
Ownership and live Windows state remain unverified, even for a consistent report.
"""
from __future__ import annotations
import sys
sys.dont_write_bytecode=True
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
from safe_files import windows_relative_parts

ROOT=Path(__file__).resolve().parents[1]
PIN_PATH=ROOT/'source/privilege/oracle-7.2.22-pin.json'
SCRIPT_NAMES=('privileged_session_worker.ps1','vbox_sup_standalone.ps1',
              'vbox_sup_start_owned.ps1','vbox_sup_cleanup.ps1',
              'vbox_sup_partial_cleanup.ps1','vbox_sup_package_identity.ps1')
MAX_JSON=131072
MAX_ENTRIES=4096

class ObservationError(ValueError):
    """A bounded diagnostic code without private paths or receipt contents."""


def _stamp(s):
    return (s.st_dev,s.st_ino,s.st_mode,s.st_size,s.st_mtime_ns,s.st_ctime_ns,s.st_nlink,
            getattr(s,'st_file_attributes',0))


def _safe_stat(s, directory):
    if stat.S_ISLNK(s.st_mode) or getattr(s,'st_file_attributes',0)&0x400:
        raise ObservationError('LINK_OR_REPARSE')
    if (directory and not stat.S_ISDIR(s.st_mode)) or (not directory and not stat.S_ISREG(s.st_mode)):
        raise ObservationError('UNEXPECTED_FILE_TYPE')
    if not directory and s.st_nlink!=1:
        raise ObservationError('HARDLINK_OR_UNKNOWN_LINK_COUNT')


def _checked_path(path, *, directory=False, optional=False):
    path=Path(os.path.abspath(path))
    chain=list(reversed(path.parents))+[path]
    for index,item in enumerate(chain):
        try: info=item.lstat()
        except FileNotFoundError:
            if optional: return None
            raise ObservationError('MISSING_REQUIRED_INPUT')
        _safe_stat(info, directory if index==len(chain)-1 else True)
    return info


def _read_file(path, *, limit=None, expected_size=None):
    before=_checked_path(path)
    if limit is not None and before.st_size>limit:
        raise ObservationError('INPUT_SIZE_BOUND')
    if expected_size is not None and before.st_size!=expected_size:
        raise ObservationError('FILE_SIZE_MISMATCH')
    # On POSIX a type change after lstat must not block opening a FIFO before
    # fstat can reject it. No data is read until the opened type is verified.
    flags=os.O_RDONLY|getattr(os,'O_BINARY',0)|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_NONBLOCK',0)
    digest=hashlib.sha256();data=[];length=0
    with os.fdopen(os.open(path,flags),'rb') as stream:
        opened=os.fstat(stream.fileno());_safe_stat(opened,False)
        if _stamp(before)!=_stamp(opened): raise ObservationError('INPUT_CHANGED')
        while True:
            chunk=stream.read(1024*1024)
            if not chunk: break
            length+=len(chunk)
            if length>before.st_size or (limit is not None and length>limit):
                raise ObservationError('INPUT_CHANGED')
            digest.update(chunk)
            if limit is not None: data.append(chunk)
        if length!=before.st_size or _stamp(opened)!=_stamp(os.fstat(stream.fileno())):
            raise ObservationError('INPUT_CHANGED')
    if _stamp(before)!=_stamp(_checked_path(path)): raise ObservationError('INPUT_CHANGED')
    return digest.hexdigest(), b''.join(data) if limit is not None else None


def _unique_object(pairs):
    result={}
    for key,value in pairs:
        if key in result: raise ObservationError('DUPLICATE_JSON_KEY')
        result[key]=value
    return result


def _json(path, *, with_digest=False):
    digest,data=_read_file(path,limit=MAX_JSON)
    try:
        value=json.loads(data.decode('utf-8-sig'),object_pairs_hook=_unique_object,
                         parse_constant=lambda _: (_ for _ in ()).throw(ObservationError('INVALID_JSON_NUMBER')))
    except (UnicodeError,json.JSONDecodeError,RecursionError):
        raise ObservationError('INVALID_JSON') from None
    if not isinstance(value,dict): raise ObservationError('INVALID_JSON_OBJECT')
    return (value,digest) if with_digest else value


def _manifest(path,pin):
    doc=_json(path);rows=doc.get('files');expected={};folded=set();total=0
    if not isinstance(rows,list) or not 1<=len(rows)<=MAX_ENTRIES:
        raise ObservationError('INVALID_MANIFEST')
    for row in rows:
        if not isinstance(row,dict): raise ObservationError('INVALID_MANIFEST_ROW')
        name,size,digest=row.get('path'),row.get('size'),row.get('sha256')
        if not isinstance(name,str) or '\\' in name or len(name)>240:
            raise ObservationError('INVALID_MANIFEST_PATH')
        windows_relative_parts(name)
        if name.casefold() in folded or name.casefold()=='.prepared.json':
            raise ObservationError('DUPLICATE_MANIFEST_PATH')
        if type(size) is not int or not 0<=size<=512*1024*1024 or not isinstance(digest,str) or not re.fullmatch('[a-f0-9]{64}',digest):
            raise ObservationError('INVALID_MANIFEST_ROW')
        folded.add(name.casefold());expected[name]=(size,digest);total+=size
    canonical=''.join(name+'\t'+str(size)+'\t'+digest+'\n' for name,(size,digest) in sorted(expected.items()))
    if (type(doc.get('file_count')) is not int or doc['file_count']!=len(rows) or
        type(doc.get('total_bytes')) is not int or doc['total_bytes']!=total or
        len(rows)!=pin.get('file_count') or total!=pin.get('total_bytes') or
        hashlib.sha256(canonical.encode('utf-8')).hexdigest()!=pin.get('manifest_rows_sha256')):
        raise ObservationError('PINNED_MANIFEST_MISMATCH')
    return expected


def _script_rows(sources):
    expected={}
    for name,path in sources.items():
        if len(windows_relative_parts(name))!=1: raise ObservationError('INVALID_SCRIPT_NAME')
        info=_checked_path(path)
        if info.st_size>MAX_JSON: raise ObservationError('SCRIPT_SIZE_BOUND')
        digest,_=_read_file(path,expected_size=info.st_size)
        expected[name]=(info.st_size,digest)
    if not expected or len(expected)>32: raise ObservationError('SCRIPT_INVENTORY_BOUND')
    return expected


def _tree(root,expected,allow_manifest=False):
    found={};directories=set();seen=set();entries=0
    for name in expected:
        directories.update(str(p).replace('\\','/') for p in Path(name).parents if str(p)!='.')
    def walk(folder,prefix=''):
        nonlocal entries
        before=_checked_path(folder,directory=True)
        children=[]
        with os.scandir(folder) as iterator:
            for item in iterator:
                entries+=1
                if entries>MAX_ENTRIES: raise ObservationError('TREE_SIZE_BOUND')
                children.append(item)
        children.sort(key=lambda x:x.name)
        for item in children:
            relative=prefix+item.name
            windows_relative_parts(relative)
            if relative.casefold() in seen: raise ObservationError('CASE_COLLISION')
            # DirEntry.stat caches Windows enumeration metadata, whose
            # ino/dev/nlink are zero. Fresh lstat preserves the hardlink check.
            seen.add(relative.casefold());info=Path(item.path).lstat()
            if stat.S_ISDIR(info.st_mode):
                _safe_stat(info,True)
                if relative not in directories: raise ObservationError('UNEXPECTED_DIRECTORY')
                walk(Path(item.path),relative+'/')
            else:
                _safe_stat(info,False)
                if allow_manifest and relative=='.prepared.json': continue
                if relative not in expected: raise ObservationError('UNEXPECTED_FILE')
                size,digest=expected[relative]
                actual,_=_read_file(Path(item.path),expected_size=size)
                if actual!=digest: raise ObservationError('FILE_HASH_MISMATCH')
                found[relative]=actual
        if _stamp(before)!=_stamp(_checked_path(folder,directory=True)):
            raise ObservationError('TREE_CHANGED')
    exists=_checked_path(root,directory=True,optional=True) is not None
    if exists: walk(root)
    missing=sorted(set(expected)-set(found))
    return {'state':'FILES_ABSENT' if not found else 'INTACT' if not missing else 'PARTIAL',
            'present_count':len(found),'missing_count':len(missing),'missing':missing,
            'directory_present':exists}


def _snapshot(session,files,scripts,pin):
    _checked_path(session,directory=True)
    app=session/'app64';code=session/'code'
    oracle=_tree(app,files,allow_manifest=True);script=_tree(code,scripts)
    manifest_copy='ABSENT';proof_digests={}
    if _checked_path(app/'.prepared.json',optional=True) is not None:
        if _manifest(app/'.prepared.json',pin)!=files: raise ObservationError('MANIFEST_COPY_MISMATCH')
        manifest_copy='PIN_MATCH'
        proof_digests['manifest']=_read_file(app/'.prepared.json',limit=MAX_JSON)[0]
    cleanup='ABSENT';marker='ABSENT'
    if _checked_path(session/'cleanup/cleanup-results.json',optional=True) is not None:
        row,proof_digests['cleanup']=_json(session/'cleanup/cleanup-results.json',with_digest=True)
        if (type(row.get('cleanup_verified')) is not bool or
            type(row.get('driver_package_removed')) is not bool or
            not isinstance(row.get('errors'),list) or
            any(not isinstance(x,str) for x in row['errors'])):
            raise ObservationError('INVALID_CLEANUP_CLAIM')
        cleanup='CLAIMS_VERIFIED' if row['cleanup_verified'] and row['driver_package_removed'] and not row['errors'] else 'CLAIMS_INCOMPLETE'
    if _checked_path(session/'payload-removed.json',optional=True) is not None:
        row,proof_digests['removed']=_json(session/'payload-removed.json',with_digest=True)
        if row!={'protected_payload_removed':True} or type(row['protected_payload_removed']) is not bool:
            raise ObservationError('INVALID_PAYLOAD_MARKER')
        marker='CLAIMS_REMOVED'
    return {'oracle_payload':oracle,'script_payload':script,'manifest_copy':manifest_copy,
            'cleanup_receipt':cleanup,'payload_removed_marker':marker,'_proof_digests':proof_digests}


def reconcile(session,manifest,expected_pin,script_sources):
    result={'schema':1,'status':'BLOCKED','resume_authorized':False,'ownership':'UNVERIFIED',
            'system_state':'NOT_OBSERVED','diagnostic_only':True,'errors':[]}
    try:
        session=Path(os.path.abspath(session));manifest=Path(os.path.abspath(manifest))
        manifest_digest=_read_file(manifest,limit=MAX_JSON)[0]
        files=_manifest(manifest,expected_pin);scripts=_script_rows(script_sources)
        before=_snapshot(session,files,scripts,expected_pin)
        after=_snapshot(session,files,scripts,expected_pin)
        if (before!=after or _manifest(manifest,expected_pin)!=files or
            _read_file(manifest,limit=MAX_JSON)[0]!=manifest_digest or _script_rows(script_sources)!=scripts):
            raise ObservationError('OBSERVATION_CHANGED')
        after.pop('_proof_digests')
        result.update(after)
        if after['payload_removed_marker']=='CLAIMS_REMOVED' and (
            after['oracle_payload']['directory_present'] or after['script_payload']['directory_present']):
            raise ObservationError('REMOVED_MARKER_CONTRADICTS_FILES')
        result['status']='REVIEW_ONLY'
    except ObservationError as exc: result['errors']=[str(exc)]
    except OSError: result['errors']=['READ_UNAVAILABLE']
    except (ValueError,TypeError,KeyError,RecursionError): result['errors']=['INVALID_INPUT']
    return result


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('session',type=Path)
    parser.add_argument('--manifest',required=True,type=Path,help='Original pinned app64/.prepared.json; never rewritten')
    args=parser.parse_args(argv)
    try: pin=_json(PIN_PATH)
    except (OSError,ValueError):
        result={'schema':1,'status':'BLOCKED','resume_authorized':False,'ownership':'UNVERIFIED',
                'system_state':'NOT_OBSERVED','diagnostic_only':True,'errors':['PIN_UNAVAILABLE']}
    else:
        result=reconcile(args.session,args.manifest,pin,{name:ROOT/'scripts'/name for name in SCRIPT_NAMES})
    print(json.dumps(result,ensure_ascii=True,sort_keys=True))
    return 0 if result['status']=='REVIEW_ONLY' else 3

if __name__=='__main__': raise SystemExit(main())
