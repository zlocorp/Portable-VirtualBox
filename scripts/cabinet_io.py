"""Cabinet.dll FDI with application-owned Unicode file I/O.

Native code receives only an opaque cabinet token, never filesystem paths.
All actual opens use Python's Unicode-aware file API. FDI callbacks may read
only that cabinet and create only selected, validated files in a private tree.
No SetupAPI installer behavior, process invocation, or automatic execution.
"""
from __future__ import annotations
import ctypes as C
import os
from pathlib import Path
from msi_staging import MAX_FILE_BYTES, MAX_TOTAL_BYTES, identifier, regular_file

U32=C.c_uint32
I32=C.c_int32
IPTR=C.c_ssize_t


class _Error(C.Structure):
    _fields_=[('operation',C.c_int),('kind',C.c_int),('present',C.c_int)]


class _Notification(C.Structure):
    _fields_=[('size',I32),('name',C.c_char_p),('disk',C.c_char_p),
              ('path',C.c_char_p),('user',C.c_void_p),('handle',IPTR),
              ('date',C.c_uint16),('time',C.c_uint16),('attributes',C.c_uint16),
              ('set_id',C.c_uint16),('cabinet',C.c_uint16),('folder',C.c_uint16),
              ('error',C.c_int)]


ALLOC=C.CFUNCTYPE(C.c_void_p,U32)
FREE=C.CFUNCTYPE(None,C.c_void_p)
OPEN=C.CFUNCTYPE(IPTR,C.c_char_p,C.c_int,C.c_int)
READ=C.CFUNCTYPE(U32,IPTR,C.c_void_p,U32)
WRITE=C.CFUNCTYPE(U32,IPTR,C.c_void_p,U32)
CLOSE=C.CFUNCTYPE(C.c_int,IPTR)
SEEK=C.CFUNCTYPE(I32,IPTR,I32,C.c_int)
NOTIFY=C.CFUNCTYPE(IPTR,C.c_int,C.POINTER(_Notification))


def iterate(cabinet, target=None, selected=None):
    if os.name!='nt': raise OSError('Native Windows cabinet API required')
    source=Path(cabinet)
    source_stat=regular_file(source)
    if source_stat.st_size>1024*1024*1024: raise ValueError('Cabinet exceeds input limit')
    if selected is not None:
        if not isinstance(selected,dict): raise ValueError('Expected selected filename/size map')
        for name,size in selected.items():
            identifier(name)
            if type(size) is not int or not 0<=size<=MAX_FILE_BYTES: raise ValueError('Invalid selected size')
    dll=C.CDLL('cabinet.dll',use_last_error=True,winmode=0x800)
    create=dll.FDICreate
    create.argtypes=[ALLOC,FREE,OPEN,READ,WRITE,CLOSE,SEEK,C.c_int,C.POINTER(_Error)]
    create.restype=C.c_void_p
    copy=dll.FDICopy
    copy.argtypes=[C.c_void_p,C.c_char_p,C.c_char_p,C.c_int,NOTIFY,C.c_void_p,C.c_void_p]
    copy.restype=C.c_int
    destroy=dll.FDIDestroy
    destroy.argtypes=[C.c_void_p]; destroy.restype=C.c_int
    errors=[]; allocations={}; streams={}; entries=[]; names=set()
    allocated=0; next_handle=1; total=0

    def guard(kind, failure, *, cleanup=False):
        def decorator(function):
            @kind
            def callback(*args):
                if errors and not cleanup: return failure
                try: return function(*args)
                except Exception as exc:
                    if not errors: errors.append(exc)
                    return failure
            return callback
        return decorator

    def register(file, limit, output):
        nonlocal next_handle
        if len(streams)>=64:
            file.close(); raise ValueError('Too many open cabinet streams')
        handle=next_handle; next_handle+=1
        streams[handle]=(file,limit,output)
        return handle

    @guard(ALLOC,None)
    def allocate(size):
        nonlocal allocated
        if size>64*1024*1024 or allocated+size>128*1024*1024:
            raise MemoryError('Cabinet memory budget exceeded')
        buffer=C.create_string_buffer(max(1,size)); address=C.addressof(buffer)
        allocations[address]=(buffer,size); allocated+=size
        return address

    @guard(FREE,None,cleanup=True)
    def free(address):
        nonlocal allocated
        if address:
            allocation=allocations.pop(address,None)
            if allocation is None: raise ValueError('Unknown native allocation')
            allocated-=allocation[1]

    @guard(OPEN,-1)
    def open_source(name,flags,mode):
        if name!=b'input.cab' or flags & 3 or flags & (0x100|0x200|0x400):
            raise ValueError('Unexpected native cabinet file request')
        file=source.open('rb')
        opened=os.fstat(file.fileno())
        if (opened.st_dev,opened.st_ino,opened.st_size)!=(source_stat.st_dev,source_stat.st_ino,source_stat.st_size):
            file.close(); raise ValueError('Cabinet source changed before open')
        return register(file,opened.st_size,False)

    @guard(READ,0xffffffff)
    def read(handle,buffer,count):
        if count>16*1024*1024: raise ValueError('Oversized native read request')
        file,limit,output=streams[handle]
        if output: raise ValueError('Unexpected read from output')
        data=file.read(count)
        if data: C.memmove(buffer,data,len(data))
        return len(data)

    @guard(WRITE,0xffffffff)
    def write(handle,buffer,count):
        file,limit,output=streams[handle]
        if not output or count>16*1024*1024 or file.tell()+count>limit:
            raise ValueError('Native write exceeds selected file bounds')
        written=file.write(C.string_at(buffer,count))
        if written!=count: raise OSError('Incomplete cabinet output write')
        return written

    @guard(CLOSE,-1,cleanup=True)
    def close(handle):
        file,_,_=streams.pop(handle); file.close(); return 0

    @guard(SEEK,-1)
    def seek(handle,distance,origin):
        file,limit,output=streams[handle]
        if output or origin not in (0,1,2): raise ValueError('Unsupported cabinet seek')
        position=file.seek(distance,origin)
        if not 0<=position<=limit: raise ValueError('Native seek outside cabinet input')
        return position

    @guard(NOTIFY,-1)
    def notify(kind,pointer):
        nonlocal total
        data=pointer.contents
        if kind in (0,5): return 0
        if kind in (1,4): raise ValueError('Spanning cabinets are not supported')
        if kind==2:
            name=identifier((data.name or b'').decode('ascii',errors='strict'))
            size=int(data.size)
            if name.casefold() in names: raise ValueError('Duplicate cabinet filename')
            if not 0<=size<=MAX_FILE_BYTES: raise ValueError('Cabinet file exceeds bounds')
            names.add(name.casefold()); entries.append((name,size)); total+=size
            if len(entries)>10000 or total>MAX_TOTAL_BYTES: raise ValueError('Cabinet exceeds limits')
            if selected is None or name not in selected: return 0
            if selected[name]!=size: raise ValueError('Cabinet size differs from MSI')
            # Ignore every executable/attribute hint; this operation only creates bytes.
            file=(Path(target)/name).open('xb')
            return register(file,size,True)
        if kind==3:
            file,limit,output=streams[data.handle]
            if not output or file.tell()!=limit: raise ValueError('Incomplete native file extraction')
            file.flush(); os.fsync(file.fileno())
            close(data.handle)
            if errors: return 0
            return 1
        raise ValueError('Unknown cabinet notification')

    state=_Error(); context=None
    try:
        context=create(allocate,free,open_source,read,write,close,seek,-1,C.byref(state))
        if not context:
            if errors: raise errors[0]
            raise OSError(f'FDICreate failed: {state.operation}/{state.kind}')
        if not copy(context,b'input.cab',b'',0,notify,None,None):
            if errors: raise errors[0]
            raise OSError(f'FDICopy failed: {state.operation}/{state.kind}')
        if errors: raise errors[0]
        if any(output for _,_,output in streams.values()): raise ValueError('Unclosed cabinet output')
    finally:
        if context: destroy(context)
        for file,_,_ in streams.values(): file.close()
        streams.clear(); allocations.clear()
    if errors: raise errors[0]
    return entries
