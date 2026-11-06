"""Windows read-only MSI data access and file-only cabinet expansion.

No MSI action/session, installer execution, COM registration or service API.
Only use hash-verified packages in private staging directories on a trusted host.
"""
from __future__ import annotations
from contextlib import contextmanager
import ctypes as C
import os
from pathlib import Path
from msi_staging import identifier, regular_file

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
    return C.WinDLL(name,use_last_error=True,winmode=0x800)


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


def _iterate(cabinet,target=None,selected=None):
    from cabinet_io import iterate
    return iterate(cabinet,target,selected)


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
