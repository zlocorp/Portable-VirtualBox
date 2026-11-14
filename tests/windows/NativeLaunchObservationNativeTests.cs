// TEST ONLY. These tests require Windows and the runner's fixed harmless child.
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace PortableVBox {
 public static partial class NativeLaunchObservationTests {
  static int unresolved,totalNativeCalls,nativeCases;
  // Root each attempt before entering CreateProcessW. Cleanup never trusts a counter.
  static readonly List<NativeLaunchAttempt> attempts=new List<NativeLaunchAttempt>();
  static bool AllHandlesDrained() {
   foreach(var attempt in attempts) if(!attempt.Handles.SafeToCleanup) return false;
   return true;
  }
  static void NativeCase(string name,ChildMode mode,NativeFault fault,string expectation) {
   var fixture=new NativeLaunchFixture();
   var attempt=new NativeLaunchAttempt(fixture);
   attempts.Add(attempt);
   try {
    var expected=fixture.Expected();
    if(expectation=="hash") expected.ImageHash=new string('0',64);
    if(expectation=="build") expected.BuildId="wrong-build";
    if(expectation=="generation") ++expected.ParentGeneration;
    attempt.Observe(mode,fault,expected);
    bool mustCreate=expectation=="" && fault!=NativeFault.BeforeEvidence && fault!=NativeFault.LaunchEntered && fault!=NativeFault.MissingImage;
    if(mustCreate) Check(attempt.Created && attempt.NativeCalls==1,"Expected fixed child was not actually created: "+name);
    bool mustInject=fault!=NativeFault.None && fault!=NativeFault.MissingImage && fault!=NativeFault.ShortTimeout;
    if(mustInject) Check(attempt.ObservedFault==fault,"Requested fault site was not actually reached: "+name);
    else Check(attempt.ObservedFault==NativeFault.None,"Native observation was mislabeled as injection: "+name);
    if(fault==NativeFault.EvidenceAfterLaunch) Check(attempt.EvidencePoisoned,"Post-launch evidence injection did not poison recorder");
    if(expectation!="" || fault==NativeFault.BeforeEvidence) {
     Check(attempt.NativeCalls==0,"Pre-call refusal invoked native creation: "+name);
     Check(attempt.Facts.Axis=="NOT_INVOKED_THIS_ATTEMPT","Pre-call refusal lost invocation axis: "+name);
     Check(!attempt.Facts.ExitObserved,"Uncreated child received fabricated exit: "+name);
    } else if(fault==NativeFault.LaunchEntered) {
     Check(attempt.NativeCalls==0 && attempt.Facts.Axis=="LAUNCH_ENTERED_UNKNOWN","Entered injected exception changed meaning");
     Check(attempt.Facts.Overall=="UNKNOWN","Entered exception certified absence");
    } else if(fault==NativeFault.MissingImage) {
     Check(attempt.NativeCalls==1 && attempt.CreateReturnedFalse,"Missing image needs actual native FALSE");
     Check(attempt.CreateError==2,"Fixed missing image should produce ERROR_FILE_NOT_FOUND");
     Check(attempt.Facts.Axis=="CREATE_REJECTED_THIS_ATTEMPT" && !attempt.Facts.ExitObserved,"Native rejection is not worker exit");
    } else if(fault==NativeFault.ControlledWaitFailed) {
     Check(attempt.HasRetainedHandle && !attempt.ProcessHandleClosed,"Controlled WAIT_FAILED closed retained handle early");
     Check(!attempt.Facts.ExitObserved && attempt.Facts.Overall=="UNKNOWN","WAIT_FAILED was treated as exit");
     Console.WriteLine(attempt.Report(name+"-before-trusted-drain"));
     Check(attempt.DrainTrusted(),"Explicit trusted drain failed after controlled WAIT_FAILED");
     Check(attempt.Facts.Overall=="UNKNOWN","Explicit drain cleared prior UNKNOWN");
    }
    if(attempt.Created) {
     Check(attempt.Facts.ExitObserved && !attempt.HasRetainedHandle && attempt.ProcessHandleClosed,"Created fixture was not genuinely drained: "+name);
     Check(attempt.NativeWaitSignals>0 && attempt.ExitCodeReads>0,"Close lacked a native signal and exit-code read: "+name);
     Check(File.Exists(Path.Combine(fixture.Root,"started.marker")),"Fixed child did not write start marker: "+name);
     Check(File.Exists(Path.Combine(fixture.Root,"exited.marker")),"Fixed child did not write completion marker: "+name);
     uint want=mode==ChildMode.Nonzero?70u:mode==ChildMode.Exit259?259u:0u;
     Check(attempt.Facts.ExitCode==want,"Wrong genuine exit code: "+name);
     if(fault==NativeFault.None) {
      Check(attempt.Facts.Overall=="OBSERVED" && attempt.IdentityVerified,"Successful native observation failed: "+name);
      Check(NativeObservedIdentity.Matches(attempt.ChildPid,attempt.ChildGeneration,attempt.ChildPid,attempt.ChildGeneration),"Native identity cannot match itself");
      Check(!NativeObservedIdentity.Matches(attempt.ChildPid,attempt.ChildGeneration,attempt.ChildPid,attempt.ChildGeneration+1),"Native same-PID different-generation was adopted");
     } else Check(attempt.Facts.Overall=="UNKNOWN","Fault lost sticky UNKNOWN after drain: "+name);
    }
    if(fault==NativeFault.ShortTimeout) Check(attempt.TimeoutObserved,"Expected actual short timeout while fixed child lives");
    if(fault==NativeFault.AfterNativeSuccess) Check(!attempt.IdentityVerified,"Injected setup fault should precede metadata");
    if(fault==NativeFault.UnverifiableIdentity) Check(!attempt.IdentityVerified,"Unverifiable identity was accepted");
    int count=attempt.NativeCalls;
    Refuses(()=>attempt.Observe(mode,NativeFault.None,fixture.Expected()),"Consumed attempt relaunched: "+name);
    Check(attempt.NativeCalls==count,"Refused second attempt reached CreateProcessW: "+name);
    Check(!attempt.Facts.MutationAuthorized,"Observation granted mutation: "+name);
    Console.WriteLine(attempt.Report(name));
    ++nativeCases;
   } finally {
    // Deliberate controlled failures receive a separate exact-handle trusted drain.
    // Persistent native failure is an explicit unresolved result, never close/kill.
    try { if(attempt.HasRetainedHandle) attempt.DrainTrusted(); }
    finally {
     totalNativeCalls+=attempt.NativeCalls;
     if(!attempt.Handles.SafeToCleanup) {
      ++unresolved;
      Console.WriteLine(attempt.Report(name+"-UNRESOLVED-PRESERVED"));
      attempt.CloseEvidenceOnly();
     } else {
      attempt.CloseEvidenceOnly();
      fixture.DeleteGeneratedFiles();
     }
    }
   }
  }
  public static int Main(string[] args) {
   if(args.Length!=0) { Console.Error.WriteLine("No command, resume, PID or executable inputs are accepted");return 2; }
   if(Environment.OSVersion.Platform!=PlatformID.Win32NT) { Console.WriteLine("SKIP native launch observations: Windows required");return 0; }
   int result=1;
   try {
    Console.WriteLine("{\"kind\":\"runner_configuration\",\"target_framework\":\".NETFramework,Version=v4.8\",\"target_platform\":\"x64\",\"mutation_authorized\":false}");
    RunManaged();
    string inspection=NativeProcessRuntimeInspection.Capture();
    if(System.Text.Encoding.UTF8.GetByteCount(inspection)>131072) throw new InvalidOperationException("Runtime inspection bound exceeded");
    File.WriteAllText(Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location),"runtime-process-inspection.json"),inspection);
    NativeCase("native-false-missing-image",ChildMode.Immediate,NativeFault.MissingImage,"");
    NativeCase("precall-evidence-failure",ChildMode.Immediate,NativeFault.BeforeEvidence,"");
    foreach(string mismatch in new[]{"hash","build","generation"}) NativeCase("precall-wrong-"+mismatch,ChildMode.Immediate,NativeFault.None,mismatch);
    NativeCase("launch-entered-injected-exception",ChildMode.Immediate,NativeFault.LaunchEntered,"");
    foreach(ChildMode mode in new[]{ChildMode.Immediate,ChildMode.Nonzero,ChildMode.Exit259,ChildMode.Delayed}) NativeCase("success-"+mode,mode,NativeFault.None,"");
    foreach(NativeFault fault in new[]{NativeFault.AfterNativeSuccess,NativeFault.WaitWrapper,NativeFault.ShortTimeout,
     NativeFault.ControlledWaitFailed,NativeFault.UnverifiableIdentity,NativeFault.EvidenceAfterLaunch})
     NativeCase("injection-or-timeout-"+fault,ChildMode.Delayed,fault,"");
    Check(unresolved==0 && AllHandlesDrained(),"Unresolved native handle remains; generated files preserved");
    Console.WriteLine("{\"kind\":\"native_contracts\",\"status\":\"PASS\",\"checks\":"+checks+",\"cases\":"+nativeCases+",\"native_calls\":"+totalNativeCalls+",\"mutation_authorized\":false}");
    result=0;
   } catch(Exception error) {
    string message=error.GetType().FullName+": "+error.Message;
    if(message.Length>2048) message=message.Substring(0,2048);
    Console.WriteLine("{\"kind\":\"native_contract_failure\",\"mutation_authorized\":false,\"error\":"+NativeLaunchAttempt.Json(message)+"}");
   } finally {
    if(AllHandlesDrained()) File.WriteAllText(Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location),"safe-to-cleanup"),"All created fixture process handles drained, or no fixture was created.");
   }
   return result;
  }
 }
}
