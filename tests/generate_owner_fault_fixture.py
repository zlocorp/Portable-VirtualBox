"""TEST ONLY: reversible import-declaration instrumentation, never a production build."""
from pathlib import Path
import hashlib,json,sys
ROOT=Path(__file__).resolve().parents[1]
CREATE=b'''  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,ExactSpelling=true,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool CreateProcessW(string application,StringBuilder command,IntPtr processSecurity,IntPtr threadSecurity,
   [MarshalAs(UnmanagedType.Bool)] bool inherit,uint flags,IntPtr environment,string directory,ref ExtendedStartup startup,out ProcessInformation process);'''
PAIRS=[(b'internal sealed class FixedEffectWorker : IDisposable {',b'internal sealed partial class FixedEffectWorker : IDisposable {'),
(CREATE,CREATE.replace(b'ExactSpelling=true,',b'EntryPoint="CreateProcessW",ExactSpelling=true,').replace(b'extern bool CreateProcessW(',b'extern bool FaultNativeCreateProcessW('))]
for result,name,args in [('uint','WaitForSingleObject','IntPtr handle,uint milliseconds'),('bool','GetExitCodeProcess','IntPtr process,out uint code'),('bool','CloseHandle','IntPtr handle')]:
 attr=b' [return:MarshalAs(UnmanagedType.Bool)]' if result=='bool' else b''
 old=b'  [DllImport("kernel32.dll",SetLastError=true)]'+attr+f' static extern {result} {name}({args});'.encode()
 new=old.replace(b'SetLastError=true',f'EntryPoint="{name}",SetLastError=true'.encode()).replace(f'extern {result} {name}('.encode(),f'extern {result} FaultNative{name}('.encode())
 PAIRS.append((old,new))
def declaration_pairs(source):
 if b'\r' in source:
  rest=source.replace(b'\r\n',b'')
  if b'\r' in rest or b'\n' in rest:raise ValueError('Mixed source line endings')
  return [(old.replace(b'\n',b'\r\n'),new.replace(b'\n',b'\r\n')) for old,new in PAIRS]
 return PAIRS
def generate(source):
 pairs=declaration_pairs(source)
 generated=source
 for old,new in pairs:
  if generated.count(old)!=1 or new in generated:raise ValueError('Import declaration drift or duplicate')
  generated=generated.replace(old,new)
 reversed_source=generated
 for old,new in reversed(pairs):
  if reversed_source.count(new)!=1:raise ValueError('Reverse declaration mismatch')
  reversed_source=reversed_source.replace(new,old)
 if reversed_source!=source:raise ValueError('Owner body/source changed')
 return generated,dict(schema=1,source_sha256=hashlib.sha256(source).hexdigest(),generated_sha256=hashlib.sha256(generated).hexdigest(),reversible_source_identity=True,declaration_replacements=len(pairs),line_ending="CRLF" if b"\r\n" in source else "LF",unchanged_bodies=['all method bodies','RunCore','Prepare','ObserveAndWait','RetainUnknown','Dispose','CloseKnown','CloseParentWriters','FinishCapture','JoinReader','Reader.Read','ReleaseAllowed'],scope='test-only synthetic import boundary; not shipped binary')
def main():
 if len(sys.argv)!=2:raise SystemExit('One existing private output directory required')
 directory=Path(sys.argv[1]);source=(ROOT/'source/privilege/FixedEffectWorker.cs').read_bytes();data,manifest=generate(source)
 for name,content in [('FixedEffectWorker.instrumented.cs',data),('owner-fault-source-manifest.json',(json.dumps(manifest,indent=2)+'\n').encode())]:
  with (directory/name).open('xb') as f:f.write(content)
 print(json.dumps(manifest))
if __name__=='__main__':main()
