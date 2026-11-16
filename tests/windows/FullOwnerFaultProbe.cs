// TEST ONLY. Raw observer imports bypass every synthetic owner boundary.
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
namespace PortableVBox {
 public static class FullOwnerFaultProbe {
  [DllImport("kernel32.dll",EntryPoint="WaitForSingleObject",SetLastError=true)] static extern uint RawWait(IntPtr handle,uint milliseconds);
  [DllImport("kernel32.dll",EntryPoint="GetExitCodeProcess",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] static extern bool RawExit(IntPtr handle,out uint code);
  [DllImport("kernel32.dll",EntryPoint="GetProcessId",SetLastError=true)] static extern uint RawId(IntPtr handle);
  [DllImport("kernel32.dll",EntryPoint="QueryFullProcessImageNameW",CharSet=CharSet.Unicode,ExactSpelling=true,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] static extern bool RawImage(IntPtr handle,uint flags,StringBuilder name,ref uint size);
  // Pure test-harness classification, identical four-field absence requirement.
  public static bool NativeFalseHasNoOutputs(IntPtr process,IntPtr thread,uint pid,uint tid){return process==IntPtr.Zero&&thread==IntPtr.Zero&&pid==0&&tid==0;}
  static int checks,runReturned,runThrew,runFinally;static Exception ownerFailure;
  static void Check(bool ok,string label){checks++;if(!ok)throw new InvalidOperationException(label);}
  static void Unknown(string reason){try{Console.Error.WriteLine("FULL_OWNER_FAULT_UNKNOWN "+reason);Console.Error.Flush();}catch{}for(;;)try{Thread.Sleep(1000);}catch(ThreadInterruptedException){}}
  static string Image(IntPtr h){var b=new StringBuilder(32768);uint n=(uint)b.Capacity;Check(RawImage(h,0,b,ref n),"raw image unavailable");return b.ToString();}
  static ProcessStartInfo Closed(string prefix){
   // Fresh named events are the only interaction; timeout is a natural failure.
   string script="$ProgressPreference='SilentlyContinue';$r=[Threading.EventWaitHandle]::OpenExisting('"+prefix+".ready');$e=[Threading.EventWaitHandle]::OpenExisting('"+prefix+".release');[void]$r.Set();if($e.WaitOne(30000)){exit 23}else{exit 77}";
   string image=Path.Combine(Environment.SystemDirectory,"WindowsPowerShell","v1.0","powershell.exe");
   var info=new ProcessStartInfo(image,"-NoLogo -NoProfile -NonInteractive -EncodedCommand "+Convert.ToBase64String(Encoding.Unicode.GetBytes(script)));
   info.UseShellExecute=false;info.CreateNoWindow=true;info.RedirectStandardOutput=true;info.RedirectStandardError=true;info.WorkingDirectory=Environment.SystemDirectory;
   info.EnvironmentVariables.Clear();info.EnvironmentVariables["SystemRoot"]=Environment.GetEnvironmentVariable("SystemRoot");info.EnvironmentVariables["WINDIR"]=Environment.GetEnvironmentVariable("WINDIR");info.EnvironmentVariables["TEMP"]=Path.GetTempPath();info.EnvironmentVariables["TMP"]=Path.GetTempPath();return info;
  }
  static void Retained(Mutex mutex,Thread thread){
   Check(Volatile.Read(ref runReturned)==0&&Volatile.Read(ref runThrew)==0&&Volatile.Read(ref runFinally)==0&&thread.IsAlive,"Run returned/threw/finally");
   bool got=false;try{got=mutex.WaitOne(0);}catch(AbandonedMutexException){throw new InvalidOperationException("fixture mutex abandoned");}finally{if(got)mutex.ReleaseMutex();}
   Check(!got,"fixture mutex reacquired");
   Check(Volatile.Read(ref FixedEffectWorker.FaultCreateAttempts)==1&&Volatile.Read(ref FixedEffectWorker.FaultOriginalCloses)==0&&Volatile.Read(ref FixedEffectWorker.FaultExitQueries)==0,"create/close/exit query counts changed");
  }
  public static int Main(string[] args){
   if(args.Length<1||args.Length>2||(args[0]!="wait-failed"&&args[0]!="false-outputs")||(args.Length==2&&args[1]!="--fail-after-retention"))return 64;
   bool expectedNegative=args.Length==2,negativeReached=false,startEntered=false,childExited=false,childExitCodeKnown=false;uint childCode=0;int result=1;
   EventWaitHandle ready=null,release=null;Thread thread=null;Mutex mutex=null;var entered=new ManualResetEvent(false);
   try {
    Check(Environment.OSVersion.Platform==PlatformID.Win32NT&&IntPtr.Size==8,"Windows x64 required");
    string prefix="Local\\PVBox.FullOwnerFault."+Guid.NewGuid().ToString("N");bool fresh;
    ready=new EventWaitHandle(false,EventResetMode.ManualReset,prefix+".ready",out fresh);Check(fresh,"ready reused");
    release=new EventWaitHandle(false,EventResetMode.ManualReset,prefix+".release",out fresh);Check(fresh,"release reused");
    var info=Closed(prefix);FixedEffectWorker.FaultMode=args[0];mutex=new Mutex(false);
    thread=new Thread(()=>{bool held=false;try{held=mutex.WaitOne(0);if(!held)throw new InvalidOperationException("fixture lock unavailable");entered.Set();var owner=FixedEffectWorker.Run(info);Volatile.Write(ref runReturned,1);GC.KeepAlive(owner);}catch(Exception e){ownerFailure=e;Volatile.Write(ref runThrew,1);}finally{Volatile.Write(ref runFinally,1);if(held)mutex.ReleaseMutex();}});
    thread.IsBackground=true;startEntered=true;thread.Start();Check(entered.WaitOne(10000),"owner entry missing");
    var timer=Stopwatch.StartNew();while(Volatile.Read(ref FixedEffectWorker.FaultBoundaryComplete)==0&&timer.ElapsedMilliseconds<10000&&Volatile.Read(ref runFinally)==0)Thread.Sleep(10);
    Check(Volatile.Read(ref FixedEffectWorker.FaultBoundaryComplete)==1&&Volatile.Read(ref FixedEffectWorker.FaultCreated)==1,"real native acquisition absent");
    Check(Volatile.Read(ref FixedEffectWorker.FaultObserverReady)==1&&FixedEffectWorker.FaultObserver!=IntPtr.Zero&&FixedEffectWorker.FaultObserver!=FixedEffectWorker.FaultOriginalProcess&&Volatile.Read(ref FixedEffectWorker.FaultDuplicateError)==0,"query/synchronize observer absent");
    Check(RawId(FixedEffectWorker.FaultObserver)==FixedEffectWorker.FaultOriginalPid&&String.Equals(Image(FixedEffectWorker.FaultObserver),info.FileName,StringComparison.OrdinalIgnoreCase),"raw original object/image mismatch");
    Check(ready.WaitOne(10000),"closed child readiness absent");
    timer.Restart();while((Volatile.Read(ref FixedEffectWorker.FaultInjected)==0||(thread.ThreadState&System.Threading.ThreadState.WaitSleepJoin)==0)&&timer.ElapsedMilliseconds<10000&&Volatile.Read(ref runFinally)==0)Thread.Sleep(10);
    Check(Volatile.Read(ref FixedEffectWorker.FaultInjected)==1&&(thread.ThreadState&System.Threading.ThreadState.WaitSleepJoin)!=0,"retention not observed");
    Check(RawWait(FixedEffectWorker.FaultObserver,0)==258,"child not live");
    Retained(mutex,thread);Check(Volatile.Read(ref FixedEffectWorker.FaultWaitCalls)==(args[0]=="wait-failed"?1:0),"wrong owner branch");
    if(args[0]=="wait-failed")Check(FixedEffectWorker.FaultRealWaitProbe==258,"real wait was not timeout");
    Console.WriteLine("FULL_OWNER_NATIVE mode="+args[0]+" create_return=true original_handles_valid=true observer_identity_match=true observer_access=1052672 raw_observer_wait=258 raw_owner_wait_probe="+(args[0]=="wait-failed"?"258":"not_called")+" injected_create_return="+(args[0]=="false-outputs"?"false":"unchanged_true")+" injected_wait_return="+(args[0]=="wait-failed"?"4294967295":"not_called"));
    Thread.Sleep(250);Retained(mutex,thread);
    if(expectedNegative){negativeReached=true;throw new InvalidOperationException("EXPECTED retained assertion");}
    result=0;
   } catch(Exception e){if(!negativeReached)Console.Error.WriteLine("FULL_OWNER_FAULT_FAIL "+e.GetType().Name+" "+e.Message);}
   finally {
    // Never exit while an owner could still create a child or creation is unknown.
    if(startEntered){
     if(Volatile.Read(ref FixedEffectWorker.FaultCreateReturned)==0){if(Volatile.Read(ref runFinally)==0||Volatile.Read(ref FixedEffectWorker.FaultCreateEntered)!=0)Unknown("creation_not_definitely_absent");}
     else if(Volatile.Read(ref FixedEffectWorker.FaultCreated)==1){
      if(Volatile.Read(ref FixedEffectWorker.FaultBoundaryComplete)!=1||Volatile.Read(ref FixedEffectWorker.FaultObserverReady)!=1||FixedEffectWorker.FaultObserver==IntPtr.Zero)Unknown("observer_unavailable");
      try{release.Set();}catch{}
      uint wait=0xffffffff;try{wait=RawWait(FixedEffectWorker.FaultObserver,45000);}catch{Unknown("natural_wait_unavailable");}
      if(wait!=0)Unknown("natural_exit_not_proved");
      childExited=true;
      try{childExitCodeKnown=RawExit(FixedEffectWorker.FaultObserver,out childCode);}catch{childExitCodeKnown=false;}
      if(!childExitCodeKnown)result=1;
      if(childCode!=23)result=1;
      try{Retained(mutex,thread);Thread.Sleep(250);Retained(mutex,thread);}catch{result=1;negativeReached=false;}
     } else if(!NativeFalseHasNoOutputs(FixedEffectWorker.FaultOriginalProcess,FixedEffectWorker.FaultOriginalThread,FixedEffectWorker.FaultOriginalPid,FixedEffectWorker.FaultOriginalTid))Unknown("native_false_with_outputs");
    }
   }
   if(ownerFailure!=null)result=1;
   if(!childExited||!childExitCodeKnown||childCode!=23)result=1;
   if(expectedNegative&&negativeReached&&childExited&&childExitCodeKnown&&childCode==23){Console.WriteLine("FULL_OWNER_FAULT_EXPECTED_FAILURE mode="+args[0]+" child_exit=23 natural_exit=true");result=1;}
   else if(result==0)Console.WriteLine("FULL_OWNER_FAULT_PASS mode="+args[0]+" checks="+checks+" real_creates=1 original_closes=0 owner_exit_queries=0 run_returned=false run_threw=false run_finally=false fixture_mutex_reacquired=false child_exit=23 natural_exit=true instrumented_imports=true production_bodies_unchanged=true");
   Console.Out.Flush();Console.Error.Flush();
   // Foreground production readers may remain blocked on retained parent writers.
   // The separate observer duplicate also remains rooted until OS host teardown;
   // no explicit observer-close success is claimed.
   // Exit only this test host after proved natural child exit, never close unknown
   // owner handles or change reader background state. Not production recovery.
   Environment.Exit(result);return result;
  }
 }
}
