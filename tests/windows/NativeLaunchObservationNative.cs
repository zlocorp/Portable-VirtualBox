// TEST ONLY. Exact handle observation for a single fixed harmless fixture.
// Do not copy this prototype into the privileged helper or treat its reports as authority.
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace PortableVBox {
 internal enum ChildMode { Immediate,Delayed,Nonzero,Exit259 }
 internal enum NativeFault { None,MissingImage,BeforeEvidence,LaunchEntered,AfterNativeSuccess,WaitWrapper,
  ShortTimeout,ControlledWaitFailed,UnverifiableIdentity,EvidenceAfterLaunch }
 internal sealed class NativeExpectedIdentity {
  internal string ImageHash,BuildId;
  internal uint ParentPid;
  internal long ParentGeneration;
 }
 internal static class NativeLaunchApi {
  internal const uint WAIT_OBJECT_0=0,WAIT_TIMEOUT=258,WAIT_FAILED=0xffffffff,INFINITE=0xffffffff;
  [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
  internal struct StartupInfo {
   internal int cb;
   internal string reserved,desktop,title;
   internal uint x,y,xSize,ySize,xCountChars,yCountChars,fillAttribute,flags;
   internal ushort showWindow,reserved2;
   internal IntPtr reservedPointer,stdInput,stdOutput,stdError;
  }
  [StructLayout(LayoutKind.Sequential)]
  internal struct ProcessInformation {
   internal IntPtr process,thread;
   internal uint processId,threadId;
  }
  [StructLayout(LayoutKind.Sequential)]
  internal struct FileTime {
   internal uint low,high;
   internal long Value {get{return unchecked((long)(((ulong)high<<32)|low));}}
  }
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true,ExactSpelling=true)]
  [return:MarshalAs(UnmanagedType.Bool)]
  internal static extern bool CreateProcessW(string application,StringBuilder command,IntPtr processSecurity,
   IntPtr threadSecurity,[MarshalAs(UnmanagedType.Bool)] bool inheritHandles,uint flags,IntPtr environment,
   string directory,ref StartupInfo startup,out ProcessInformation information);
  [DllImport("kernel32.dll",SetLastError=true)] internal static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
  [DllImport("kernel32.dll",SetLastError=true)]
  [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool GetExitCodeProcess(IntPtr handle,out uint code);
  [DllImport("kernel32.dll",SetLastError=true)]
  [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll")] internal static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll")] internal static extern uint GetCurrentProcessId();
  [DllImport("kernel32.dll",SetLastError=true)] internal static extern uint GetProcessId(IntPtr handle);
  [DllImport("kernel32.dll",SetLastError=true)]
  [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool GetProcessTimes(IntPtr handle,out FileTime created,out FileTime exited,out FileTime kernel,out FileTime user);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true,ExactSpelling=true)]
  [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool QueryFullProcessImageNameW(IntPtr handle,uint flags,StringBuilder path,ref uint size);
  internal static long Creation(IntPtr handle) {
   FileTime created,exited,kernel,user;
   if(!GetProcessTimes(handle,out created,out exited,out kernel,out user)) throw new InvalidOperationException("GetProcessTimes failed: "+Marshal.GetLastWin32Error());
   if(created.Value<=0) throw new InvalidOperationException("Unverifiable native generation");
   return created.Value;
  }
 }
 internal sealed class NativeLaunchFixture {
  internal const string BuildId="test-only-native-launch-fixture-v1";
  internal readonly string Root,AttemptId,ImagePath,ImageHash;
  internal readonly uint ParentPid;
  internal readonly long ParentGeneration;
  readonly FileStream imageLease;
  internal NativeLaunchFixture() {
   AttemptId=Guid.NewGuid().ToString("N");
   Root=Path.Combine(Path.GetTempPath(),"pvbox-native-launch-"+AttemptId);
   Directory.CreateDirectory(Root);
   using(var owner=new FileStream(Path.Combine(Root,"fixture.owner"),FileMode.CreateNew,FileAccess.Write,FileShare.Read)) {
    byte[] bytes=Encoding.ASCII.GetBytes(AttemptId);owner.Write(bytes,0,bytes.Length);owner.Flush(true);
   }
   ImagePath=Path.Combine(Root,"NativeLaunchFixtureChild.exe");
   string source=Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location),"NativeLaunchFixtureChild.exe");
   File.Copy(source,ImagePath,false);
   imageLease=new FileStream(ImagePath,FileMode.Open,FileAccess.Read,FileShare.Read);
   ImageHash=HashHeldImage();
   ParentPid=NativeLaunchApi.GetCurrentProcessId();
   ParentGeneration=NativeLaunchApi.Creation(NativeLaunchApi.GetCurrentProcess());
  }
  internal string HashHeldImage() {
   imageLease.Position=0;
   using(var hash=SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(imageLease)).Replace("-","").ToLowerInvariant();
  }
  internal NativeExpectedIdentity Expected() {
   return new NativeExpectedIdentity { ImageHash=ImageHash,BuildId=BuildId,ParentPid=ParentPid,ParentGeneration=ParentGeneration };
  }
  internal void DeleteGeneratedFiles() {
   imageLease.Dispose();
   // Deliberately no recursive cleanup or deletion selected by evidence contents.
   foreach(string name in new[]{"started.marker","exited.marker","release.marker","observation.jsonl","NativeLaunchFixtureChild.exe","fixture.owner"}) {
    string path=Path.Combine(Root,name);if(File.Exists(path)) File.Delete(path);
   }
   Directory.Delete(Root,false);
  }
 }
 internal sealed class NativeLaunchAttempt {
  readonly NativeLaunchFixture fixture;
  readonly NativeObservationRecorder recorder;
  readonly List<string> events=new List<string>();
  internal readonly NativeObservationFacts Facts=new NativeObservationFacts();
  internal readonly NativeRetainedHandles Handles=new NativeRetainedHandles();
  IntPtr process {get{return Handles.Process;}}
  IntPtr thread {get{return Handles.Thread;}}
  bool deferControlledDrain;
  bool gateReleased;
  ChildMode childMode;
  internal int NativeCalls,NativeWaitCalls,NativeWaitSignals,ExitCodeReads,CreateError,WaitError;
  internal bool Created,CreateReturnedFalse,ProcessHandleClosed,IdentityVerified,TimeoutObserved,DrainUnresolved;
  internal uint ChildPid;
  internal long ChildGeneration;
  internal string ChildImage="";
  NativeFault fault;
  NativeFault observedFault;
  internal NativeFault ObservedFault {
   get {
    if(fault==NativeFault.BeforeEvidence && recorder.ObservedFault==RecorderFault.BeforeWrite) return NativeFault.BeforeEvidence;
    if(fault==NativeFault.EvidenceAfterLaunch && recorder.ObservedFault==RecorderFault.AfterWrite) return NativeFault.EvidenceAfterLaunch;
    return observedFault;
   }
  }
  internal bool EvidencePoisoned {get{return recorder.Poisoned;}}
  internal bool HasRetainedHandle {get{return process!=IntPtr.Zero;}}
  internal bool HasRetainedThread {get{return thread!=IntPtr.Zero;}}
  internal NativeLaunchAttempt(NativeLaunchFixture value) {
   fixture=value;recorder=new NativeObservationRecorder(Path.Combine(value.Root,"observation.jsonl"),RecorderFault.None);
  }
  void Event(string value) { if(events.Count<24) events.Add(value); }
  static string Quoted(string value) {
   if(value.IndexOf('"')>=0 || value.IndexOf('\r')>=0 || value.IndexOf('\n')>=0)
    throw new InvalidOperationException("Unsupported fixture path");
   return "\""+value+"\"";
  }
  void Validate(NativeExpectedIdentity expected) {
   if(expected==null || expected.BuildId!=NativeLaunchFixture.BuildId ||
      expected.ImageHash!=fixture.ImageHash || expected.ImageHash!=fixture.HashHeldImage())
    throw new InvalidOperationException("Expected fixed image/build mismatch");
   uint pid=NativeLaunchApi.GetCurrentProcessId();
   long generation=NativeLaunchApi.Creation(NativeLaunchApi.GetCurrentProcess());
   if(!NativeObservedIdentity.Matches(pid,generation,expected.ParentPid,expected.ParentGeneration))
    throw new InvalidOperationException("Expected parent generation mismatch");
  }
  void Record(string stage) {
   recorder.Append("{\"stage\":"+Json(stage)+",\"attempt_id\":"+Json(fixture.AttemptId)+",\"axis\":"+Json(Facts.Axis)+
    ",\"overall\":"+Json(Facts.Overall)+",\"mutation_authorized\":false}");
  }
  internal void Observe(ChildMode mode,NativeFault injected,NativeExpectedIdentity expected) {
   Facts.UseOnce(); // A second request throws before any recorder/native action.
   fault=injected;
   childMode=mode;
   try {
    Validate(expected);
    if(fault==NativeFault.BeforeEvidence) recorder.Fault=RecorderFault.BeforeWrite;
    Record("PRECALL_READY");
    string image=fault==NativeFault.MissingImage?Path.Combine(fixture.Root,"fixed-missing-fixture.exe"):fixture.ImagePath;
    var command=new StringBuilder(Quoted(image)+" "+Quoted(fixture.Root)+" "+fixture.AttemptId+" "+mode);
    var startup=new NativeLaunchApi.StartupInfo();startup.cb=Marshal.SizeOf(typeof(NativeLaunchApi.StartupInfo));
    NativeLaunchApi.ProcessInformation information;
    Facts.EnterLaunch();Record("LAUNCH_ENTERED_UNKNOWN");
    if(fault==NativeFault.LaunchEntered) {
     observedFault=NativeFault.LaunchEntered;
     throw new InvalidOperationException("INJECTED exception after launch entry, before native call");
    }
    ++NativeCalls; // P/Invoke invocation attempt; no-return cannot prove native execution.
    Handles.NativeCallEntered=true;
    bool created=NativeLaunchApi.CreateProcessW(image,command,IntPtr.Zero,IntPtr.Zero,false,0,IntPtr.Zero,fixture.Root,ref startup,out information);
    if(!created) {
     int error=Marshal.GetLastWin32Error(); // Immediate capture, before any other native operation.
     Handles.NativeReturnObserved=true;Handles.NativeRejected=true;
     CreateError=error;CreateReturnedFalse=true;
     Facts.NativeRejected(error);Event("native_FALSE_error_"+error);Record("CREATE_REJECTED_THIS_ATTEMPT");
     return;
    }
    // Retain both original handles before ANY fallible metadata, logging or bookkeeping.
    Handles.Process=information.process;
    Handles.Thread=information.thread;
    Handles.NativeReturnObserved=true;
    Created=true;
    Facts.Retained();
    if(fault==NativeFault.AfterNativeSuccess) {
     observedFault=NativeFault.AfterNativeSuccess;
     throw new InvalidOperationException("INJECTED post-native-success setup fault before metadata");
    }
    CloseThread();
    Event("native_TRUE_original_handle_retained");
    ChildPid=NativeLaunchApi.GetProcessId(process);
    ChildGeneration=NativeLaunchApi.Creation(process);
    var path=new StringBuilder(1024);uint size=1024;
    if(!NativeLaunchApi.QueryFullProcessImageNameW(process,0,path,ref size)) throw new InvalidOperationException("Native image query failed: "+Marshal.GetLastWin32Error());
    ChildImage=path.ToString();
    long identityGeneration=fault==NativeFault.UnverifiableIdentity?0:ChildGeneration; // Do not overwrite the actual observed generation.
    if(fault==NativeFault.UnverifiableIdentity) observedFault=NativeFault.UnverifiableIdentity;
    if(ChildPid!=information.processId || !NativeObservedIdentity.Matches(ChildPid,identityGeneration,information.processId,ChildGeneration) ||
       !String.Equals(ChildImage,fixture.ImagePath,StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Child identity unverifiable");
    IdentityVerified=true;
    if(fault==NativeFault.EvidenceAfterLaunch) recorder.Fault=RecorderFault.AfterWrite;
    Record("EXACT_CHILD_RETAINED");
    if(fault==NativeFault.WaitWrapper) {
     observedFault=NativeFault.WaitWrapper;
     throw new InvalidOperationException("INJECTED managed wait-wrapper exception");
    }
    if(fault==NativeFault.ControlledWaitFailed) {
     observedFault=NativeFault.ControlledWaitFailed;
     Event("INJECTED_WAIT_FAILED_no_native_wait");Facts.Poison("INJECTED WAIT_FAILED");deferControlledDrain=true;return;
    }
    if(fault!=NativeFault.ShortTimeout) ReleaseFixtureGate();
    uint wait=WaitNative(fault==NativeFault.ShortTimeout?0u:15000u);
    if(wait==NativeLaunchApi.WAIT_OBJECT_0) ReadExitAndClose();
    else if(wait==NativeLaunchApi.WAIT_TIMEOUT) { TimeoutObserved=true;Event("native_WAIT_TIMEOUT");Facts.Poison("Native timeout"); }
    else { Facts.Poison("Native wait failed/unsupported result");DrainUnresolved=true; }
   } catch(Exception error) {
    Facts.Poison(error.GetType().Name+": "+error.Message);
   } finally {
    CloseThread();
    if(HasRetainedHandle && !deferControlledDrain) DrainTrusted();
    if(!recorder.Poisoned) {
     try {Record("OBSERVATION_END");} catch(Exception error) {Facts.Poison(error.Message);}
    }
   }
  }
  uint WaitNative(uint timeout) {
   ++NativeWaitCalls;
   uint result=NativeLaunchApi.WaitForSingleObject(process,timeout);
   if(result==NativeLaunchApi.WAIT_FAILED) {
    int error=Marshal.GetLastWin32Error();WaitError=error;Event("native_WAIT_FAILED_error_"+error);
   }
   if(result==NativeLaunchApi.WAIT_OBJECT_0) {++NativeWaitSignals;Event("native_WAIT_OBJECT_0");}
   return result;
  }
  void ReadExitAndClose() {
   // Called only after a genuine native WAIT_OBJECT_0, never by exit-code polling.
   uint code;
   ++ExitCodeReads;
   if(!NativeLaunchApi.GetExitCodeProcess(process,out code)) throw new InvalidOperationException("Native exit-code read failed: "+Marshal.GetLastWin32Error());
   Facts.SignaledExit(code);
   Event("native_exit_code_"+code);
   if(!NativeLaunchApi.CloseHandle(process)) throw new InvalidOperationException("Native process-handle close failed: "+Marshal.GetLastWin32Error());
   Handles.Process=IntPtr.Zero;Handles.ProcessExitAndCloseVerified=true;ProcessHandleClosed=true;DrainUnresolved=false;
   Event("original_process_handle_closed_after_exit");
  }
  void CloseThread() {
   if(thread==IntPtr.Zero) return;
   if(NativeLaunchApi.CloseHandle(thread)) Handles.Thread=IntPtr.Zero;
   else { Facts.Poison("Native thread-handle close failed: "+Marshal.GetLastWin32Error());DrainUnresolved=true; }
  }
  internal bool DrainTrusted() {
   deferControlledDrain=false;
   if(!HasRetainedHandle) return Facts.ExitObserved;
   try {ReleaseFixtureGate();}
   catch(Exception error) {Facts.Poison("Fixture release write fault; waiting for finite natural exit: "+error.Message);}
   try {
    // No reopen/adoption by PID, no cancellation, termination, or timeout-based close.
    uint result=WaitNative(NativeLaunchApi.INFINITE);
    if(result!=NativeLaunchApi.WAIT_OBJECT_0) {
     Facts.Poison("Trusted exact-handle drain unresolved");DrainUnresolved=true;return false;
    }
    ReadExitAndClose();
    return true;
   } catch(Exception error) {
    Facts.Poison("Trusted drain fault: "+error.Message);DrainUnresolved=true;return false;
   }
  }
  void ReleaseFixtureGate() {
   if(childMode!=ChildMode.Delayed || gateReleased) return;
   using(var release=new FileStream(Path.Combine(fixture.Root,"release.marker"),FileMode.CreateNew,FileAccess.Write,FileShare.Read)) {
    byte[] token=Encoding.ASCII.GetBytes(fixture.AttemptId);release.Write(token,0,token.Length);release.Flush(true);
   }
   gateReleased=true;
  }
  internal void CloseEvidenceOnly() { recorder.Dispose(); }
  internal static string Json(string text) {
   var output=new StringBuilder("\"");
   foreach(char c in text) {
    if(c=='"' || c=='\\') output.Append('\\').Append(c);
    else if(c<32 || c>126) output.Append("\\u").Append(((int)c).ToString("x4"));
    else output.Append(c);
   }
   return output.Append('"').ToString();
  }
  internal string Report(string name) {
   var output=new StringBuilder();
   output.Append("{\"kind\":\"native_observation\",\"case\":").Append(Json(name));
   output.Append(",\"attempt_id\":").Append(Json(fixture.AttemptId));
   output.Append(",\"scenario\":").Append(Json(fault.ToString()));
   output.Append(",\"observed_injection\":").Append(Json(ObservedFault.ToString()));
   output.Append(",\"observed_recorder_injection\":").Append(Json(recorder.ObservedFault.ToString()));
   output.Append(",\"axis\":").Append(Json(Facts.Axis)).Append(",\"overall\":").Append(Json(Facts.Overall));
   output.Append(",\"reason\":").Append(Json(Facts.Reason));
   output.Append(",\"mutation_authorized\":false,\"native_calls\":").Append(NativeCalls);
   output.Append(",\"native_calls_scope\":\"P/Invoke invocation attempts; unavailable return does not prove native execution\"");
   output.Append(",\"native_entry_recorded\":").Append(Handles.NativeCallEntered?"true":"false");
   output.Append(",\"native_return_observed\":").Append(Handles.NativeReturnObserved?"true":"false");
   output.Append(",\"native_wait_calls\":").Append(NativeWaitCalls).Append(",\"native_wait_signals\":").Append(NativeWaitSignals);
   output.Append(",\"create_returned_false\":").Append(CreateReturnedFalse?"true":"false").Append(",\"create_error\":").Append(CreateError);
   output.Append(",\"parent_pid\":").Append(fixture.ParentPid).Append(",\"parent_generation\":").Append(Json(fixture.ParentGeneration.ToString()));
   output.Append(",\"child_pid\":").Append(ChildPid).Append(",\"child_generation\":").Append(Json(ChildGeneration.ToString()));
   output.Append(",\"fixture_image_sha256\":").Append(Json(fixture.ImageHash)).Append(",\"child_image\":").Append(Json(ChildImage));
   output.Append(",\"identity_verified\":").Append(IdentityVerified?"true":"false");
   output.Append(",\"exit_observed\":").Append(Facts.ExitObserved?"true":"false").Append(",\"exit_code\":").Append(Facts.ExitObserved?Facts.ExitCode.ToString():"null");
   output.Append(",\"timeout_observed\":").Append(TimeoutObserved?"true":"false");
   output.Append(",\"process_handle_retained\":").Append(HasRetainedHandle?"true":"false").Append(",\"process_handle_closed\":").Append(ProcessHandleClosed?"true":"false");
   bool unresolved=DrainUnresolved || (Handles.NativeCallEntered && !Handles.NativeReturnObserved);
   output.Append(",\"drain_unresolved\":").Append(unresolved?"true":"false").Append(",\"native_wait_error\":").Append(WaitError);
   output.Append(",\"evidence_poisoned\":").Append(recorder.Poisoned?"true":"false").Append(",\"evidence_records_acknowledged\":").Append(recorder.AcknowledgedRecords);
   output.Append(",\"events\":[");
   for(int i=0;i<events.Count;i++) {if(i!=0) output.Append(',');output.Append(Json(events[i]));}
   return output.Append("]}").ToString();
  }
 }
}
