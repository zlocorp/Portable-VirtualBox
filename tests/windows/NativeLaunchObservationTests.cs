// TEST ONLY. Managed protocol checks are not Windows launch evidence.
using System;
using System.IO;

namespace PortableVBox {
 public static partial class NativeLaunchObservationTests {
  static int checks;
  static void Check(bool condition,string message) {
   ++checks;
   if(!condition) throw new InvalidOperationException(message);
  }
  static void Refuses(Action action,string message) {
   bool refused=false;
   try { action(); } catch(InvalidOperationException) { refused=true; }
   Check(refused,message);
  }
  static string TemporaryRoot() {
   string path=Path.Combine(Path.GetTempPath(),"pvbox-launch-managed-"+Guid.NewGuid().ToString("N"));
   Directory.CreateDirectory(path);
   return path;
  }
  public static int RunManaged() {
   checks=0;
   string root=TemporaryRoot();
   try {
    string path=Path.Combine(root,"ack.jsonl");
    using(var recorder=new NativeObservationRecorder(path,RecorderFault.None)) {
     recorder.Append("{\"stage\":\"before-launch\",\"mutation_authorized\":false}");
     Check(recorder.AcknowledgedRecords==1,"A real write/flush/readback must precede acknowledgment");
     Check(recorder.AcknowledgedBytes==new FileInfo(path).Length,"Acknowledged bytes must be written");
     Check(!recorder.Poisoned,"Successful readback unexpectedly poisoned");
    }
    foreach(RecorderFault fault in new[]{RecorderFault.BeforeWrite,RecorderFault.AfterWrite,RecorderFault.BeforeFlush,
     RecorderFault.AfterFlush,RecorderFault.BeforeReadback,RecorderFault.AfterReadback}) {
     using(var recorder=new NativeObservationRecorder(Path.Combine(root,fault+".jsonl"),fault)) {
      Refuses(()=>recorder.Append("{\"mutation_authorized\":false}"),"Injected storage fault must refuse: "+fault);
      Check(recorder.Poisoned,"Storage fault did not poison: "+fault);
      Check(recorder.ObservedFault==fault,"Requested injection must be witnessed at its actual recorder stage: "+fault);
      Check(recorder.AcknowledgedRecords==0,"Uncertain append was acknowledged: "+fault);
      Refuses(()=>recorder.Append("{}"),"Poisoned writer cannot resume: "+fault);
     }
    }
    using(var recorder=new NativeObservationRecorder(Path.Combine(root,"oversize.jsonl"),RecorderFault.None)) {
     Refuses(()=>recorder.Append(new string('x',4097)),"Oversize record must refuse");
     Check(recorder.Poisoned && recorder.AcknowledgedBytes==0,"Oversize record must not be written");
    }
    using(var recorder=new NativeObservationRecorder(Path.Combine(root,"count.jsonl"),RecorderFault.None)) {
     for(int i=0;i<32;i++) recorder.Append("{}");
     Refuses(()=>recorder.Append("{}"),"Recorder must enforce its record bound");
     Check(recorder.AcknowledgedRecords==32,"Bounded recorder count changed on refusal");
    }
    using(var recorder=new NativeObservationRecorder(Path.Combine(root,"unicode-boundary.jsonl"),RecorderFault.None)) {
     recorder.Append(new string('\u0436',2047));
     Check(recorder.AcknowledgedBytes==4095,"UTF-8 byte boundary must include newline");
     Refuses(()=>recorder.Append(new string('\u0436',2048)),"Multibyte record must enforce byte limit");
    }
    using(var recorder=new NativeObservationRecorder(Path.Combine(root,"invalid-surrogate.jsonl"),RecorderFault.None)) {
     Refuses(()=>recorder.Append("\ud800"),"Malformed surrogate must not silently change recorded evidence");
     Check(recorder.Poisoned && recorder.AcknowledgedBytes==0,"Malformed Unicode must poison without write");
    }
    bool createNew=false;
    try { using(var ignored=new NativeObservationRecorder(path,RecorderFault.None)) {} }
    catch(IOException) {createNew=true;}
    Check(createNew,"Existing evidence must never be reopened or repaired");

    var facts=new NativeObservationFacts();
    Check(!facts.MutationAuthorized,"Fresh observation must deny mutation");
    Check(facts.Axis=="NOT_INVOKED_THIS_ATTEMPT","Fresh attempt must be not invoked");
    facts.UseOnce();facts.EnterLaunch();facts.Poison("injected launch-entered exception");
    Check(facts.Axis=="LAUNCH_ENTERED_UNKNOWN" && facts.Overall=="UNKNOWN","Entered fault cannot certify no launch");
    Refuses(()=>facts.UseOnce(),"Unknown attempt cannot launch again");
    facts.Retained();facts.SignaledExit(0);
    Check(facts.Axis=="EXACT_CHILD_EXITED" && facts.Overall=="UNKNOWN","Later zero exit must not erase UNKNOWN");
    Check(!facts.MutationAuthorized,"Exited observation must deny mutation");

    var rejected=new NativeObservationFacts();rejected.UseOnce();rejected.EnterLaunch();rejected.NativeRejected(2);
    Check(rejected.Axis=="CREATE_REJECTED_THIS_ATTEMPT","FALSE is local to this attempt");
    Check(!rejected.ExitObserved && !rejected.MutationAuthorized,"Uncreated child must not receive an exit or authority");
    Refuses(()=>rejected.UseOnce(),"Even a rejected attempt is single use");
    var exited=new NativeObservationFacts();exited.UseOnce();exited.EnterLaunch();exited.Retained();exited.SignaledExit(259);
    Check(exited.ExitObserved && exited.ExitCode==259,"259 after a genuine signal is an exit code");
    Check(exited.Overall=="OBSERVED" && !exited.MutationAuthorized,"Observed exit does not grant authority");
    Check(NativeObservedIdentity.Matches(123,456,123,456),"Same observed generation should match diagnostically");
    Check(!NativeObservedIdentity.Matches(123,456,123,457),"Same PID/different generation must not be adopted");
    Check(!NativeObservedIdentity.Matches(123,0,123,0),"Unverifiable generation cannot match");
    var retained=new NativeRetainedHandles();
    retained.Process=new IntPtr(1); // Managed-only sentinel, never passed to a native API.
    try { throw new InvalidOperationException("INJECTED drain bookkeeping exception"); }
    catch(InvalidOperationException) {}
    Check(!retained.SafeToCleanup,"A drain exception/missed counter update cannot authorize cleanup");
    retained.Process=IntPtr.Zero;retained.Thread=new IntPtr(2);
    Check(!retained.SafeToCleanup,"A retained thread handle must keep cleanup unresolved");
    retained.Thread=IntPtr.Zero;
    Check(retained.SafeToCleanup,"No retained handle should allow generated-file cleanup");
    retained.NativeCallEntered=true;
    Check(!retained.SafeToCleanup,"Unavailable native-call outcome with no handles must preserve fixture files");
    retained.NativeReturnObserved=true;
    Check(!retained.SafeToCleanup,"Native success without verified child exit must preserve fixture files");
    retained.ProcessExitAndCloseVerified=true;
    Check(retained.SafeToCleanup,"Verified native exit and close should permit fixture-only deletion");
    retained.ProcessExitAndCloseVerified=false;retained.NativeRejected=true;
    Check(retained.SafeToCleanup,"Actual captured FALSE without handles permits fixture-only deletion");
    Check(NativeProcessRuntimeInspection.TestManaged()==0,"Runtime metadata/IL contracts failed");
    Console.WriteLine("{\"kind\":\"managed_contracts\",\"status\":\"PASS\",\"checks\":"+checks+",\"native_calls\":0,\"mutation_authorized\":false}");
    return 0;
   } finally {
    foreach(string file in Directory.GetFiles(root)) File.Delete(file);
    Directory.Delete(root);
   }
  }
 }
}
