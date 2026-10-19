"""Temporary developer probe. File-only preparation; never installer execution."""
import ctypes as C
import shutil
import sys
import tempfile
from pathlib import Path
import prepare_app64
import windows_payload

original_bind=windows_payload._bind

def traced_bind(dll,name,args,result=windows_payload.U32):
    native=original_bind(dll,name,args,result)
    if name!='SetupIterateCabinetW': return native
    def call(path,flags,callback,context):
        counts={}
        @args[2]
        def trace(ctx,notification,p1,p2):
            counts[notification]=counts.get(notification,0)+1
            value=callback(ctx,notification,p1,p2)
            if notification==0x11 and counts[notification]<=3:
                info=C.cast(p1,C.POINTER(windows_payload._FileInCabinet)).contents
                print('CAB callback',hex(notification),repr(info.NameInCabinet),info.FileSize,'return',value,flush=True)
            return value
        print('CAB native path',repr(path),'exists',Path(path).is_file(),flush=True)
        result=native(path,flags,trace,context)
        code=C.get_last_error()
        print('CAB result',result,'last_error',code,'callbacks',counts,flush=True)
        C.set_last_error(code)
        return result
    return call
windows_payload._bind=traced_bind
original=prepare_app64.cabinet_members

def inspect_cabinet(path):
    with Path(path).open('rb') as source: header=source.read(48)
    print('CAB boundary',Path(path).name,'size',Path(path).stat().st_size,'header',header.hex(),flush=True)
    try: return original(path)
    except OSError:
        with tempfile.TemporaryDirectory(prefix='pvbox-cab-probe-') as directory:
            copy=Path(directory)/'product.cab'; shutil.copyfile(path,copy)
            print('Trying identical bytes at a fresh short source path',flush=True)
            try: print('Copy inventory count',len(original(copy)),flush=True)
            except Exception as exc: print('Copy inventory failed',repr(exc),flush=True)
        raise

prepare_app64.cabinet_members=inspect_cabinet
prepare_app64.prepare(Path(sys.argv[1]),Path(sys.argv[2]),sys.argv[3],'7.2.20')
