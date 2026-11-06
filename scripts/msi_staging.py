"""Bounded MSI layout planning and new-directory file assembly, never installation.

Callers own a private staging directory under a trusted parent. No protection
against an administrator replacing parent directories concurrently is claimed.
"""
from __future__ import annotations
import ctypes
from dataclasses import asdict, dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
from safe_files import windows_relative_parts

MAX_FILE_BYTES = 512 * 1024 * 1024
MAX_TOTAL_BYTES = 4 * 1024 * 1024 * 1024


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.]{0,127}', value):
        raise ValueError('Invalid MSI identifier')
    single_name(value)
    return value


def single_name(value):
    parts = windows_relative_parts(value)
    if len(parts) != 1 or len(value) > 255:
        raise ValueError('Expected a single safe Windows filename')
    return value


def _number(value, maximum, *, positive=False):
    if type(value) is int:
        n = value
    elif isinstance(value, str) and re.fullmatch('[0-9]+', value):
        n = int(value)
    else:
        raise ValueError('Expected nonnegative MSI integer')
    if n < (1 if positive else 0) or n > maximum:
        raise ValueError('MSI integer outside supported bounds')
    return n


def _target_name(value, *, directory=False):
    if not isinstance(value, str):
        raise ValueError('Invalid MSI target name')
    if directory:
        if value.count(':') > 1:
            raise ValueError('Invalid DefaultDir target:source pair')
        value = value.split(':')[0]
        if value == '.':
            return ''
    names = value.split('|')
    if len(names) not in (1, 2) or any(not x for x in names):
        raise ValueError('Invalid MSI short|long name')
    for name in names:
        single_name(name)
    return names[-1]


@dataclass(frozen=True)
class PlannedFile:
    key: str
    relative: str
    size: int
    sequence: int
    cabinet: str
    version: str = ''


@dataclass(frozen=True)
class LayoutPlan:
    files: tuple[PlannedFile, ...]
    excluded: tuple[str, ...]

    @property
    def total_bytes(self):
        return sum(x.size for x in self.files)


def build_plan(metadata, *, compressed, app_root='INSTALLDIR', max_total_bytes=MAX_TOTAL_BYTES):
    """Resolve target long filenames under INSTALLDIR and File->Media membership.

    Does not evaluate installer conditions, features, properties or custom actions.
    Conditional application payload is staged but never activated.
    """
    if type(compressed) is not bool or type(max_total_bytes) is not int or max_total_bytes <= 0:
        raise ValueError('Invalid layout policy')
    tables = {}
    for name, key in [('Directory', 'Directory'), ('Component', 'Component'), ('File', 'File'), ('Media', 'DiskId')]:
        rows = metadata.get(name)
        if not isinstance(rows, list) or not 1 <= len(rows) <= 10000:
            raise ValueError('Missing, empty or oversized MSI table: ' + name)
        index, folded = {}, set()
        for row in rows:
            if not isinstance(row, dict):
                raise ValueError('Invalid MSI row')
            value = identifier(row.get(key))
            if value.casefold() in folded:
                raise ValueError('Duplicate MSI key')
            index[value] = row; folded.add(value.casefold())
        tables[name] = index
    directories = tables['Directory']
    if app_root not in directories:
        raise ValueError('Application root not present')
    for key, row in directories.items():
        parent = row.get('Directory_Parent')
        if not isinstance(parent, str) or (parent and parent not in directories):
            raise ValueError('Invalid directory parent')
        _target_name(row.get('DefaultDir'), directory=True)
        chain, current = set(), key
        while current:
            if current in chain or len(chain) > 128:
                raise ValueError('Directory cycle/depth exceeded')
            chain.add(current)
            parent = directories[current]['Directory_Parent']
            if parent == current:
                if current != 'TARGETDIR': raise ValueError('Invalid self-parent directory')
                break
            current = parent
    cache = {app_root: ()}
    def relative(key):
        if key not in directories: raise ValueError('Component refers to missing directory')
        if key in cache: return cache[key]
        row = directories[key]; parent = row['Directory_Parent']
        base = relative(parent) if parent and parent != key else None
        name = _target_name(row['DefaultDir'], directory=True)
        cache[key] = None if base is None else base + ((name,) if name else ())
        return cache[key]
    components = tables['Component']
    for row in components.values(): relative(row.get('Directory_'))
    media, cabinet_names, previous = [], set(), 0
    for row in sorted(tables['Media'].values(), key=lambda r:_number(r['DiskId'], 32767, positive=True)):
        last = _number(row.get('LastSequence'), 32767, positive=True)
        cabinet = row.get('Cabinet')
        if not isinstance(cabinet,str): raise ValueError('Missing cabinet')
        single_name(cabinet[1:] if cabinet.startswith('#') else cabinet)
        if last <= previous or cabinet.casefold() in cabinet_names:
            raise ValueError('Ambiguous media sequence/cabinet')
        media.append((previous,last,cabinet)); previous=last; cabinet_names.add(cabinet.casefold())
    files, excluded, sequences, targets = [], [], set(), set()
    for row in tables['File'].values():
        key = row['File']; name = _target_name(row.get('FileName'))
        component = row.get('Component_')
        if component not in components: raise ValueError('Unknown file component')
        directory = relative(components[component]['Directory_'])
        size = _number(row.get('FileSize'), MAX_FILE_BYTES)
        sequence = _number(row.get('Sequence'),32767,positive=True)
        attrs = _number(row.get('Attributes') or '0', 32767)
        if sequence in sequences: raise ValueError('Duplicate file sequence')
        sequences.add(sequence)
        if attrs & 8192 or not (attrs & 16384 or compressed):
            raise ValueError('Non-cabinet source files are not supported')
        cabinets = [cab for low,high,cab in media if low < sequence <= high]
        if len(cabinets)!=1: raise ValueError('No unique media for file')
        if directory is None:
            excluded.append(key); continue
        path = '/'.join(directory+(name,)); windows_relative_parts(path)
        if path.casefold() in targets or path.casefold()=='.prepared.json':
            raise ValueError('Conflicting target filename')
        targets.add(path.casefold())
        files.append(PlannedFile(key,path,size,sequence,cabinets[0],row.get('Version','')))
    for target in targets:
        parts=target.split('/')
        if any('/'.join(parts[:i]) in targets for i in range(1,len(parts))):
            raise ValueError('File/directory target collision')
    plan=LayoutPlan(tuple(sorted(files,key=lambda x:x.sequence)),tuple(sorted(excluded)))
    if not plan.files or plan.total_bytes > max_total_bytes: raise ValueError('Empty/oversized application layout')
    return plan


def validate_members(entries, expected):
    seen, sizes, total = set(), {}, 0
    for key,size in entries:
        identifier(key); size=_number(size,MAX_FILE_BYTES)
        if key.casefold() in seen: raise ValueError('Duplicate cabinet filename')
        seen.add(key.casefold()); sizes[key]=size; total+=size
        if len(seen)>10000 or total>MAX_TOTAL_BYTES: raise ValueError('Cabinet exceeds limits')
    for item in expected:
        if sizes.get(item.key)!=item.size: raise ValueError('Cabinet file missing or size mismatch: '+item.key)


def regular_file(path):
    st=os.lstat(path)
    if not stat.S_ISREG(st.st_mode) or getattr(st,'st_file_attributes',0)&0x400:
        raise ValueError('Reparse/nonregular payload rejected')
    return st


def copy_payload(source, destination, size):
    st=regular_file(source)
    if st.st_size!=size: raise ValueError('Payload size differs from MSI')
    digest=hashlib.sha256(); count=0
    with open(source,'rb') as src, open(destination,'xb') as dst:
        opened=os.fstat(src.fileno())
        if (st.st_dev,st.st_ino,st.st_size)!=(opened.st_dev,opened.st_ino,opened.st_size):
            raise ValueError('Payload identity changed')
        while chunk:=src.read(min(1024*1024,size-count+1)):
            count+=len(chunk)
            if count>size: raise ValueError('Payload exceeds MSI size')
            digest.update(chunk); dst.write(chunk)
        if count!=size: raise ValueError('Truncated payload')
        dst.flush(); os.fsync(dst.fileno())
    return digest.hexdigest()


def publish_directory(source, destination):
    """No-replace publication. Never fall back to overwriting rename/copy."""
    if os.name=='nt': os.rename(source,destination); return
    if sys.platform.startswith('linux'):
        libc=ctypes.CDLL(None,use_errno=True)
        function=getattr(libc,'renameat2',None)
        if function is None: raise OSError('Atomic no-replace directory rename unavailable')
        function.argtypes=[ctypes.c_int,ctypes.c_char_p,ctypes.c_int,ctypes.c_char_p,ctypes.c_uint]
        function.restype=ctypes.c_int
        if function(-100,os.fsencode(source),-100,os.fsencode(destination),1)!=0:
            error=ctypes.get_errno(); raise OSError(error,os.strerror(error),str(destination))
        return
    raise OSError('No supported no-replace publication API')


def assemble(plan, payloads, destination, *, validate=None):
    """Copy verified-sized payloads into a new tree and emit its hash inventory.

    Input identities/authenticity must be established by the preparation caller.
    The optional validator runs on the complete private tree before publication.
    """
    destination=Path(destination)
    if os.path.lexists(destination): raise FileExistsError('Destination already exists')
    if not destination.parent.is_dir(): raise ValueError('Missing trusted parent directory')
    with tempfile.TemporaryDirectory(prefix='.vbox-app64-',dir=destination.parent) as work:
        stage=Path(work)/'tree'; stage.mkdir()
        rows=[]
        for item in plan.files:
            if item.key not in payloads: raise ValueError('Missing extracted payload')
            path=stage.joinpath(*windows_relative_parts(item.relative)); path.parent.mkdir(parents=True,exist_ok=True)
            sha=copy_payload(payloads[item.key],path,item.size)
            rows.append({'path':item.relative,'size':item.size,'sha256':sha,'file_key':item.key})
        details=validate(stage) if validate else {}
        report={'status':'prepared-not-installed','file_count':len(rows),'total_bytes':plan.total_bytes,
                'excluded':list(plan.excluded),'files':rows,'validation':details}
        with (stage/'.prepared.json').open('x',encoding='utf-8') as handle:
            json.dump(report,handle,ensure_ascii=False,indent=2); handle.write('\n'); handle.flush(); os.fsync(handle.fileno())
        publish_directory(stage,destination)
    return report
