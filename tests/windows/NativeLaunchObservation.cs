// TEST ONLY. No production references, launch authority, or persisted recovery API.
using System;
using System.IO;
using System.Text;
namespace PortableVBox {
 internal enum RecorderFault { None,BeforeWrite,AfterWrite,BeforeFlush,AfterFlush,BeforeReadback,AfterReadback }
 internal sealed class NativeObservationRecorder:IDisposable {
  readonly FileStream writer;
  internal RecorderFault Fault;
  internal int AcknowledgedRecords {get;private set;}
  internal long AcknowledgedBytes {get;private set;}
  internal bool Poisoned {get;private set;}
  internal RecorderFault ObservedFault {get;private set;}
  internal NativeObservationRecorder(string path,RecorderFault fault) {
   Fault=fault;
   writer=new FileStream(path,FileMode.CreateNew,FileAccess.ReadWrite,FileShare.Read,4096,FileOptions.WriteThrough);
  }
  void Inject(RecorderFault stage) {
   if(Fault==stage) {
    ObservedFault=stage;
    throw new InvalidOperationException("INJECTED recorder "+stage);
   }
  }
  internal void Append(string text) {
   if(Poisoned) throw new InvalidOperationException("Poisoned recorder cannot resume");
   try {
    if(text==null || text.Length>4095 || text.IndexOf('\n')>=0 || text.IndexOf('\r')>=0)
     throw new InvalidOperationException("Record must occupy one line");
    byte[] bytes=new UTF8Encoding(false,true).GetBytes(text+"\n");
    if(bytes.Length>4096 || AcknowledgedRecords>=32 || AcknowledgedBytes+bytes.Length>65536)
     throw new InvalidOperationException("Evidence bound exceeded");
    Inject(RecorderFault.BeforeWrite);
    long start=writer.Position;
    writer.Write(bytes,0,bytes.Length);
    Inject(RecorderFault.AfterWrite);
    Inject(RecorderFault.BeforeFlush);
    writer.Flush(true);
    Inject(RecorderFault.AfterFlush);
    Inject(RecorderFault.BeforeReadback);
    writer.Position=start;
    byte[] readback=new byte[bytes.Length];
    int offset=0;
    while(offset<readback.Length) {
     int read=writer.Read(readback,offset,readback.Length-offset);
     if(read==0) throw new IOException("Incomplete evidence readback");
     offset+=read;
    }
    for(int i=0;i<bytes.Length;i++) if(bytes[i]!=readback[i]) throw new IOException("Evidence readback mismatch");
    Inject(RecorderFault.AfterReadback);
    AcknowledgedBytes+=bytes.Length;
    ++AcknowledgedRecords;
   } catch(Exception error) {
    Poisoned=true;
    throw new InvalidOperationException("Evidence append uncertain; recorder poisoned",error);
   }
  }
  public void Dispose() { writer.Dispose(); }
 }
 internal sealed class NativeObservationFacts {
  bool used,poisoned;
  internal bool MutationAuthorized {get{return false;}}
  internal string Axis="NOT_INVOKED_THIS_ATTEMPT";
  internal string Overall {get{return poisoned?"UNKNOWN":(ExitObserved?"OBSERVED":Axis);}}
  internal string Reason="";
  internal bool ExitObserved=false;
  internal uint ExitCode=0;
  internal void UseOnce() {
   if(used) throw new InvalidOperationException("Attempt is permanently consumed");
   used=true;
  }
  internal void EnterLaunch() { Axis="LAUNCH_ENTERED_UNKNOWN"; }
  internal void Poison(string why) { poisoned=true;if(Reason=="") Reason=why; }
  internal void Retained() { Axis="EXACT_CHILD_RETAINED"; }
  internal void SignaledExit(uint code) { ExitObserved=true;ExitCode=code;Axis="EXACT_CHILD_EXITED"; }
  internal void NativeRejected(int error) { Axis="CREATE_REJECTED_THIS_ATTEMPT"; }
 }
 internal static class NativeObservedIdentity {
  internal static bool Matches(uint p,long g,uint expectedP,long expectedG) {
   return p!=0 && g>0 && p==expectedP && g==expectedG;
  }
 }
 internal sealed class NativeRetainedHandles {
  internal IntPtr Process=IntPtr.Zero,Thread=IntPtr.Zero;
  internal bool NativeCallEntered=false,NativeReturnObserved=false,NativeRejected=false,ProcessExitAndCloseVerified=false;
  internal bool SafeToCleanup {
   get {
    return Process==IntPtr.Zero && Thread==IntPtr.Zero &&
     (!NativeCallEntered || (NativeReturnObserved && (NativeRejected || ProcessExitAndCloseVerified)));
   }
  }
 }
}
