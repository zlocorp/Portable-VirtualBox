"""Windows read-only MSI data access and file-only cabinet expansion.

No MSI action/session, installer execution, COM registration or service API.
Only use hash-verified packages in private staging directories on a trusted host.
"""
from __future__ import annotations
from contextlib import contextmanager
import ctypes as C
import os
from pathlib import Path
from msi_staging import identifier, regular_file, validate_members

U32=C.c_uint32
U16=C.c_uint16
P32=C.POINTER(U32)
TABLES={
    'Directory':('Directory','Directory_Parent','DefaultDir'),
    'Component':('Component','Directory_','Attributes','Condition'),
    'File':('File','Component_','FileName','FileSize','Version','Attributes','Sequence'),
    'Media':('DiskId','LastSequence','Cabinet'),
    'Property':('Property','Value'),
}


def _dll(name):
    if os.name!='nt': raise OSError('Native Windows payload APIs required')
    return C.WinDLL(name,use_last_error=True,winmode=0x800)  # System32 only


def _bind(dll,name,args,result=U32):
    f=getattr(dll,name); f.argtypes=args; f.restype=result; return f


def _check(code,operation):
    if code: raise OSError(int(code),operation+' failed')


class MsiReader:
    """Owns a read-only database handle. All query strings come from fixed tables."""
    def __init__(self,path):
        self.path=Path(path); self.handle=U32()
        self.dll=_dll('msi.dll')
        _bind(self.dll,'MsiOpenDatabaseW',[C.c_wchar_p,C.c_void_p,P32])
        _bind(self.dll,'MsiCloseHandle',[U32])
        _bind(self.dll,'MsiDatabaseOpenViewW',[U32,C.c_wchar_p,P32])
        _bind(self.dll,'MsiViewExecute',[U32,U32])
        _bind(self.dll,'MsiViewFetch',[U32,P32])
        _bind(self.dll,'MsiRecordGetStringW',[U32,U32,C.c_wchar_p,P32])
        _bind(self.dll,'MsiRecordReadStream',[U32,U32,C.c_void_p,P32])
        _bind(self.dll,'MsiGetSummaryInformationW',[U32,C.c_wchar_p,U32,P32])
        _bind(self.dll,'MsiSummaryInfoGetPropertyW',[U32,U32,P32,C.POINTER(C.c_int),C.c_void_p,C.c_wchar_p,P32])

    def __enter__(self):
        regular_file(self.path)
        _check(self.dll.MsiOpenDatabaseW(str(self.path.resolve()),None,C.byref(self.handle)),'MsiOpenDatabase READONLY')
        return self

    def __exit__(self,*args):
        if self.handle.value:
            result=self.dll.MsiCloseHandle(self.handle); self.handle=U32()
            if args[0] is None: _check(result,'MsiCloseHandle')

    @contextmanager
    def _view(self,sql):
        if not self.handle.value: raise ValueError('MSI database is not open')
        view=U32()
        _check(self.dll.MsiDatabaseOpenViewW(self.handle,sql,C.byref(view)),'MsiDatabaseOpenView')
        try:
            _check(self.dll.MsiViewExecute(view,0),'MsiViewExecute SELECT')
            yield view
        finally: self.dll.MsiCloseHandle(view)

    def _fetch(self,view):
        record=U32(); result=self.dll.MsiViewFetch(view,C.byref(record))
        if result==259: return None
        _check(result,'MsiViewFetch'); return record

    def _string(self,record,column):
        # MSI requires a non-NULL one-character buffer for the size query.
        size=U32(0); empty=C.create_unicode_buffer(1)
        result=self.dll.MsiRecordGetStringW(record,column,empty,C.byref(size))
        if result not in (0,234): _check(result,'MsiRecordGetString size')
        if size.value>32768: raise ValueError('MSI string exceeds limit')
        buffer=C.create_unicode_buffer(size.value+1); size.value+=1
        _check(self.dll.MsiRecordGetStringW(record,column,buffer,C.byref(size)),'MsiRecordGetString')
        return buffer.value

    def table(self,name):
        columns=TABLES[name]
        sql='SELECT '+','.join('`'+c+'`' for c in columns)+' FROM `'+name+'`'
        result=[]
        with self._view(sql) as view:
            while (record:=self._fetch(view)) is not None:
                try:
                    if len(result)>=10000: raise ValueError('MSI table exceeds row limit')
                    result.append({column:self._string(record,i+1) for i,column in enumerate(columns)})
                finally: self.dll.MsiCloseHandle(record)
        return result

    def summary(self,property_id):
        if property_id not in (7,15): raise ValueError('Unsupported summary field')
        handle=U32()
        _check(self.dll.MsiGetSummaryInformationW(self.handle,None,0,C.byref(handle)),'Read summary')
        try:
            kind=U32(); integer=C.c_int(); size=U32(1024); text=C.create_unicode_buffer(1024)
            _check(self.dll.MsiSummaryInfoGetPropertyW(handle,property_id,C.byref(kind),C.byref(integer),None,text,C.byref(size)),'Summary property')
            if kind.value in (2,3): return integer.value
            if kind.value in (30,31): return text.value
            raise ValueError('Unexpected MSI summary type')
        finally: self.dll.MsiCloseHandle(handle)

    def export_stream(self,name,path,max_bytes=1024*1024*1024):
        identifier(name)
        sql="SELECT `Data` FROM `_Streams` WHERE `Name`='"+name+"'"
        with self._view(sql) as view:
            record=self._fetch(view)
            if record is None: raise ValueError('MSI cabinet stream absent')
            try:
                total=0; buffer=C.create_string_buffer(1024*1024)
                with Path(path).open('xb') as out:
                    while True:
                        size=U32(len(buffer))
                        _check(self.dll.MsiRecordReadStream(record,1,buffer,C.byref(size)),'Read MSI stream')
                        if size.value==0: break
                        total+=size.value
                        if total>max_bytes: raise ValueError('MSI stream exceeds size limit')
                        out.write(buffer.raw[:size.value])
                    out.flush(); os.fsync(out.fileno())
                if total==0: raise ValueError('Empty cabinet stream')
                extra=self._fetch(view)
                if extra is not None:
                    self.dll.MsiCloseHandle(extra); raise ValueError('Duplicate stream')
            finally: self.dll.MsiCloseHandle(record)


class _FileInCabinet(C.Structure):
    _fields_=[('NameInCabinet',C.c_wchar_p),('FileSize',U32),('Win32Error',U32),
              ('DosDate',U16),('DosTime',U16),('DosAttribs',U16),('FullTargetName',C.c_wchar*260)]


class _FilePaths(C.Structure):
    _fields_=[('Target',C.c_wchar_p),('Source',C.c_wchar_p),('Win32Error',U32),('Flags',U32)]


def _iterate(cabinet,target=None,selected=None):
    api=_dll('setupapi.dll')
    callback_type=C.WINFUNCTYPE(U32,C.c_void_p,U32,C.c_size_t,C.c_size_t)
    function=_bind(api,'SetupIterateCabinetW',[C.c_wchar_p,U32,callback_type,C.c_void_p],C.c_int)
    entries=[]; errors=[]; names=set(); total=0
    @callback_type
    def callback(context,notification,param1,param2):
        nonlocal total
        try:
            if errors: return 0 if notification==0x11 else 13
            if notification==0x10: return 0  # CABINETINFO
            if notification==0x12: raise ValueError('Spanning cabinets are not supported')
            if notification==0x13:
                detail=C.cast(param1,C.POINTER(_FilePaths)).contents
                if detail.Win32Error: raise OSError(detail.Win32Error,'Cabinet file extraction failed')
                return 0
            if notification!=0x11: raise ValueError('Unexpected cabinet notification')
            detail=C.cast(param1,C.POINTER(_FileInCabinet)).contents
            name=identifier(detail.NameInCabinet); size=int(detail.FileSize)
            if name.casefold() in names: raise ValueError('Duplicate cabinet entry')
            names.add(name.casefold()); total+=size; entries.append((name,size))
            if len(entries)>10000 or size>512*1024*1024 or total>4*1024*1024*1024:
                raise ValueError('Cabinet exceeds limits')
            if selected is None or name not in selected: return 2  # FILEOP_SKIP
            if selected[name]!=size: raise ValueError('Cabinet size changed')
            destination=Path(target)/name
            if os.path.lexists(destination): raise FileExistsError('Cabinet target exists')
            path=str(destination.resolve())
            if len(path)>=260: raise ValueError('Cabinet target exceeds supported path length')
            detail.FullTargetName=path
            return 1  # FILEOP_DOIT; only the assigned private path is written.
        except Exception as error:
            errors.append(error)
            return 0 if notification==0x11 else 13
    regular_file(cabinet)
    if not function(str(Path(cabinet).resolve()),0,callback,None):
        if errors: raise errors[0]
        raise C.WinError(C.get_last_error())
    if errors: raise errors[0]
    return entries


def cabinet_members(path):
    return _iterate(path)


def extract_cabinet(path,target,selected):
    """Write into a caller-owned private directory; reject existing output files."""
    target=Path(target)
    if not target.is_dir() or target.is_symlink(): raise ValueError('Private target directory required')
    for key in selected:
        identifier(key)
        if os.path.lexists(target/key): raise FileExistsError('Cabinet target exists')
    actual=dict(_iterate(path,target,selected))
    for key,size in selected.items():
        if actual.get(key)!=size or regular_file(target/key).st_size!=size:
            raise ValueError('Missing/truncated cabinet output')
