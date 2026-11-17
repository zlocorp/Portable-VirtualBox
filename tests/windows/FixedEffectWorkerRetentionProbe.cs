// TEST ONLY: childless fault probe against the unmodified production owner.
// The synthetic owner never acquired a process, pipe, file or privileged resource.
// Process termination below exits only this harmless probe, never an effect worker.
using System;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
namespace PortableVBox {
 public static class FixedEffectWorkerRetentionProbe {
  [DllImport("kernel32.dll",SetLastError=true)]
  static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
  static readonly BindingFlags Private=BindingFlags.Instance|BindingFlags.NonPublic;
  static int assertions;
  static void Check(bool condition,string label) {assertions++;if(!condition)throw new InvalidOperationException(label);}
  static FieldInfo Field(string name) {
   var field=typeof(FixedEffectWorker).GetField(name,Private);
   if(field==null)throw new InvalidOperationException("Missing owner field: "+name);
   return field;
  }
  static bool Flag(object owner,string name) {return (bool)Field(name).GetValue(owner);}
  static void MustRetain(Mutex held,Thread thread,ManualResetEvent completed,object owner) {
   Check(!completed.WaitOne(0),"Owner returned or threw instead of retaining");
   Check(thread.IsAlive,"Owner thread exited");
   bool acquired=false;
   try {acquired=held.WaitOne(0);}
   catch(AbandonedMutexException) {throw new InvalidOperationException("Owner abandoned its fixture lock");}
   finally {if(acquired)held.ReleaseMutex();}
   Check(!acquired,"Owner released its fixture lock");
   Check(!Flag(owner,"exited"),"Unknown wait was promoted to child exit");
   Check(!Flag(owner,"disposed")&&!Flag(owner,"finished"),"Unknown owner released capture or resources");
  }
  public static int Main() {
   int exit=1;
   try {
    Check(Environment.OSVersion.Platform==PlatformID.Win32NT&&IntPtr.Size==8,"Windows x64 required");
    // NULL is invalid and cannot be recycled. Minus one is a process pseudo-handle,
    // not a valid choice for this experiment. Capture the error before other calls.
    uint wait=WaitForSingleObject(IntPtr.Zero,0);
    int error=Marshal.GetLastWin32Error();
    Check(wait==0xffffffff&&error==6,"NULL did not produce WAIT_FAILED/ERROR_INVALID_HANDLE");
    Console.WriteLine("RETENTION_NATIVE_PROBE handle=NULL wait="+wait+" error="+error+" acquired_child=false");
    object owner=Activator.CreateInstance(typeof(FixedEffectWorker),true);
    // Match a post-return/pre-exit owner state solely in this synthetic object.
    // No native handle is invented, closed, or passed to an effect operation.
    Field("createEntered").SetValue(owner,true);
    Field("createReturned").SetValue(owner,true);
    Field("created").SetValue(owner,true);
    object original=Field("original").GetValue(owner);
    Check((IntPtr)original.GetType().GetField("Process",Private).GetValue(original)==IntPtr.Zero,"Expected zero-initialized process handle");
    MethodInfo observe=typeof(FixedEffectWorker).GetMethod("ObserveAndWait",Private);
    Check(observe!=null,"Missing actual ObserveAndWait method");
    var ready=new ManualResetEvent(false);var enter=new ManualResetEvent(false);
    var entered=new ManualResetEvent(false);var completed=new ManualResetEvent(false);
    var held=new Mutex(false);Exception failure=null;
    var thread=new Thread(()=> {
     bool owns=false;
     try {
      owns=held.WaitOne(0);if(!owns)throw new InvalidOperationException("Fixture lock unavailable");
      ready.Set();
      if(!enter.WaitOne(10000))throw new InvalidOperationException("Observer did not release entry barrier");
      entered.Set();
      observe.Invoke(owner,new object[]{new StringBuilder(32768),"closed-childless-probe",(uint)0});
     } catch(Exception e) {failure=e;}
     finally {
      // If production unexpectedly returns, release our test lock and signal failure.
      // Correct RetainUnknown never reaches this block during the observation.
      if(owns)held.ReleaseMutex();completed.Set();
     }
    });
    thread.IsBackground=true;thread.Start();
    Check(ready.WaitOne(10000),"Owner thread did not acquire lock and reach barrier");
    MustRetain(held,thread,completed,owner);
    enter.Set();Check(entered.WaitOne(10000),"Owner did not pass entry barrier");
    var deadline=Stopwatch.StartNew();bool sleeping=false;
    while(deadline.ElapsedMilliseconds<10000) {
     if(completed.WaitOne(0))throw new InvalidOperationException("Owner did not retain",failure);
     // The actual method sets observationFailure before its zero-deadline wait.
     // WaitSleepJoin after that, with no managed waits in the invocation path,
     // observes RetainUnknown's sleep rather than our earlier entry barrier.
     Thread.MemoryBarrier();
     sleeping=Field("observationFailure").GetValue(owner)!=null&&
       (thread.ThreadState&System.Threading.ThreadState.WaitSleepJoin)!=0;
     if(sleeping)break;
     Thread.Sleep(10);
    }
    Check(sleeping,"Did not observe unknown-owner retention sleep");
    MustRetain(held,thread,completed,owner);
    // Thread.Interrupt must not escape RetainUnknown into the caller's finally.
    // This is a test-thread interruption, not process termination or child control.
    for(int i=0;i<3;i++) {
     thread.Interrupt();
     Check(!completed.WaitOne(150),"Interruption released unknown owner");
     MustRetain(held,thread,completed,owner);
    }
    Check(failure==null,"Owner invocation failed");
    Console.WriteLine("FIXED_EFFECT_RETENTION_PASS assertions="+assertions+" bounded_observation_ms="+deadline.ElapsedMilliseconds+" interruptions=3 childless=true native_wait_probe=WAIT_FAILED owner_returned=false mutex_released=false");
    exit=0;
   } catch(Exception e) {Console.Error.WriteLine("FIXED_EFFECT_RETENTION_FAIL "+e);}
   // No child/native resources were acquired by the synthetic owner. Its endless
   // fail-closed loop is intentionally not unwound. Exit only this standalone
   // probe after the assertions; this is not production teardown/retry evidence.
   Console.Out.Flush();Console.Error.Flush();Environment.Exit(exit);return exit;
  }
 }
}
