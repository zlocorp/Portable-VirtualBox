// TEST ONLY: a real harmless child with a synthetic restricted-handle adoption.
// Production source is compiled unchanged. This does not exercise RunCore admission.
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
namespace PortableVBox {
 public static class FixedEffectAcquiredChildProbe {
  [StructLayout(LayoutKind.Sequential)] struct Startup {
   internal int Size;internal IntPtr Reserved,Desktop,Title;
   internal uint X,Y,XSize,YSize,XChars,YChars,Fill,Flags;
   internal ushort Show,ReservedSize;internal IntPtr ReservedBytes,Input,Output,Error;
  }
  [StructLayout(LayoutKind.Sequential)] struct ProcessInformation {internal IntPtr Process,Thread;internal uint Pid,Tid;}
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,ExactSpelling=true,SetLastError=true)]
  [return:MarshalAs(UnmanagedType.Bool)] static extern bool CreateProcessW(string application,StringBuilder command,IntPtr processSecurity,IntPtr threadSecurity,
   [MarshalAs(UnmanagedType.Bool)] bool inherit,uint flags,IntPtr environment,string directory,ref Startup startup,out ProcessInformation process);
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool DuplicateHandle(IntPtr sourceProcess,IntPtr source,IntPtr targetProcess,out IntPtr target,uint access,[MarshalAs(UnmanagedType.Bool)] bool inherit,uint options);
  [DllImport("kernel32.dll",SetLastError=true)] static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
  [DllImport("kernel32.dll",SetLastError=true)] static extern uint GetProcessId(IntPtr process);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] static extern bool GetExitCodeProcess(IntPtr process,out uint code);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,ExactSpelling=true,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool QueryFullProcessImageNameW(IntPtr process,uint flags,StringBuilder name,ref uint length);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] static extern bool CloseHandle(IntPtr handle);
  const string Prefix="Local\\PVBox.AcquiredChild.";
  static readonly BindingFlags Private=BindingFlags.Instance|BindingFlags.NonPublic;
  static int assertions;
  static void Check(bool value,string label) {assertions++;if(!value)throw new InvalidOperationException(label);}
  static bool Valid(IntPtr h) {return h!=IntPtr.Zero&&h!=new IntPtr(-1);}
  static FieldInfo Field(string name) {var f=typeof(FixedEffectWorker).GetField(name,Private);if(f==null)throw new InvalidOperationException(name);return f;}
  static bool Flag(object owner,string name) {return (bool)Field(name).GetValue(owner);}
  static void Unknown(string reason) {
   try {Console.Error.WriteLine("ACQUIRED_CHILD_UNKNOWN "+reason+" no_exit_claim=true");Console.Error.Flush();}catch { }
   for(;;)try {Thread.Sleep(1000);}catch(ThreadInterruptedException) { }
  }
  static void Native(bool ok,int error,string label) {if(!ok)throw new Win32Exception(error,label);}
  static uint Identity(IntPtr handle) {
   uint id=GetProcessId(handle);int error=id==0?Marshal.GetLastWin32Error():0;
   Native(id!=0,error,"query original/duplicate process identity");return id;
  }
  static void Live(IntPtr handle,string phase) {
   uint wait=WaitForSingleObject(handle,0);int error=wait==0xffffffff?Marshal.GetLastWin32Error():0;
   Check(wait==258,"child not live at "+phase+" wait="+wait+" error="+error);
   Console.WriteLine("ACQUIRED_CHILD_LIVE phase="+phase+" wait="+wait+" error="+error);
  }
  static string Image(IntPtr handle) {
   var text=new StringBuilder(32768);uint size=(uint)text.Capacity;
   bool ok=QueryFullProcessImageNameW(handle,0,text,ref size);int error=ok?0:Marshal.GetLastWin32Error();
   Native(ok,error,"query child image");return text.ToString();
  }
  // Cleanup of the test child is a separate harness responsibility, not production
  // recovery. A timeout or native error cannot be turned into an exit/close claim.
  static void NaturalExit(ProcessInformation original,EventWaitHandle release,ref bool exited) {
   // If signalling fails, the closed child still has its own bounded natural
   // timeout. That will fail exit-code assertions, but cannot skip exit proof.
   try {release.Set();}catch { }
   uint wait=0xffffffff;int error=0;
   try {wait=WaitForSingleObject(original.Process,45000);error=wait==0xffffffff?Marshal.GetLastWin32Error():0;}
   catch {Unknown("natural_exit_wait_unavailable");}
   if(wait!=0)Unknown("natural_exit_wait="+wait+" error="+error);
   exited=true;
  }
  static void CloseOriginal(ref IntPtr handle) {
   if(!Valid(handle))return;
   IntPtr owned=handle;handle=IntPtr.Zero;
   bool ok=CloseHandle(owned);int error=ok?0:Marshal.GetLastWin32Error();
   if(!ok)Unknown("close_original_error="+error);
  }
  static void Retained(Mutex held,Thread thread,ManualResetEvent completed,object owner) {
   Check(!completed.WaitOne(0),"production ObserveAndWait returned/threw");
   Check(thread.IsAlive,"owner thread ended");
   bool acquired=false;
   try {acquired=held.WaitOne(0);}catch(AbandonedMutexException){throw new InvalidOperationException("fixture mutex abandoned");}
   finally {if(acquired)held.ReleaseMutex();}
   Check(!acquired,"fixture mutex released");
   Check(!Flag(owner,"exited")&&!Flag(owner,"disposed")&&!Flag(owner,"finished"),"unknown promoted to release/exit");
   Check(!(bool)typeof(FixedEffectWorker).GetProperty("ExitCodeKnown",Private).GetValue(owner,null),"unknown promoted to exit code");
  }
  static int Child(string token) {
   Guid parsed;if(token.Length!=32||!Guid.TryParseExact(token,"N",out parsed)||parsed.ToString("N")!=token)return 64;
   // Names are a fixed namespace and canonical GUID, never arbitrary commands,
   // process IDs, paths, inherited handles or privileged resources.
   using(var ready=EventWaitHandle.OpenExisting(Prefix+token+".ready"))
   using(var release=EventWaitHandle.OpenExisting(Prefix+token+".release")) {
    ready.Set();return release.WaitOne(30000)?23:77;
   }
  }
  public static int Main(string[] args) {
   if(args.Length==2&&args[0]=="--closed-fixture-child")return Child(args[1]);
   string fault=null;
   if(args.Length==1&&(args[0]=="--fail-before-adoption"||args[0]=="--fail-after-retention"))fault=args[0];
   else if(args.Length!=0)return 64;
   int result=1;bool entered=false,returned=false,created=false,childExited=false,injected=false,releaseExitVerified=false;
   ProcessInformation original=new ProcessInformation();IntPtr restricted=IntPtr.Zero;
   EventWaitHandle ready=null,release=null;
   object owner=null;Thread ownerThread=null;Mutex held=null;ManualResetEvent completed=null;
   try {
    Check(Environment.OSVersion.Platform==PlatformID.Win32NT&&IntPtr.Size==8,"Windows x64 required");
    string image=Assembly.GetExecutingAssembly().Location;
    Check(System.IO.Path.IsPathRooted(image)&&image.IndexOf('"')<0,"invalid self image");
    string token=Guid.NewGuid().ToString("N");bool fresh;
    ready=new EventWaitHandle(false,EventResetMode.ManualReset,Prefix+token+".ready",out fresh);Check(fresh,"ready event reused");
    release=new EventWaitHandle(false,EventResetMode.ManualReset,Prefix+token+".release",out fresh);Check(fresh,"release event reused");
    var startup=new Startup {Size=Marshal.SizeOf(typeof(Startup))};
    var command=new StringBuilder("\""+image+"\" --closed-fixture-child "+token);
    entered=true;
    bool ok=CreateProcessW(image,command,IntPtr.Zero,IntPtr.Zero,false,0x08000000,IntPtr.Zero,System.IO.Path.GetDirectoryName(image),ref startup,out original);
    created=ok;returned=true;int createError=ok?0:Marshal.GetLastWin32Error();
    if(!ok&&(original.Process!=IntPtr.Zero||original.Thread!=IntPtr.Zero||original.Pid!=0||original.Tid!=0))Unknown("contradictory_create_outputs");
    Native(ok,createError,"create closed child");
    if(!Valid(original.Process)||!Valid(original.Thread)||original.Process==original.Thread)Unknown("invalid_original_handles");
    Check(ready.WaitOne(10000),"child readiness not observed");
    Live(original.Process,"before-adoption");
    if(fault=="--fail-before-adoption"){injected=true;throw new InvalidOperationException("EXPECTED pre-adoption assertion");}
    ok=DuplicateHandle(GetCurrentProcess(),original.Process,GetCurrentProcess(),out restricted,0x1000,false,0);
    int duplicateError=ok?0:Marshal.GetLastWin32Error();
    if(!ok&&restricted!=IntPtr.Zero)Unknown("contradictory_duplicate_output");
    Native(ok,duplicateError,"duplicate query-only child handle");
    if(!Valid(restricted)||restricted==original.Process||restricted==original.Thread)Unknown("invalid_restricted_handle");
    Check(Identity(original.Process)==original.Pid&&Identity(restricted)==original.Pid,"duplicate object identity mismatch");
    Check(String.Equals(Image(original.Process),image,StringComparison.OrdinalIgnoreCase)&&String.Equals(Image(restricted),image,StringComparison.OrdinalIgnoreCase),"actual child image mismatch");
    // No SYNCHRONIZE right. This same-object duplicate is deliberately different
    // from the full-access original produced by CreateProcess, not a close race.
    uint restrictedWait=WaitForSingleObject(restricted,0);int waitError=restrictedWait==0xffffffff?Marshal.GetLastWin32Error():0;
    Check(restrictedWait==0xffffffff&&waitError==5,"restricted wait not WAIT_FAILED/access denied");
    Console.WriteLine("ACQUIRED_CHILD_NATIVE acquired_child=true synthetic_adoption=true restricted_access=4096 wait="+restrictedWait+" error="+waitError+" identity_match=true");
    owner=Activator.CreateInstance(typeof(FixedEffectWorker),true);
    Field("createEntered").SetValue(owner,true);Field("createReturned").SetValue(owner,true);Field("created").SetValue(owner,true);
    object adopted=Field("original").GetValue(owner);
    adopted.GetType().GetField("Process",Private).SetValue(adopted,restricted);
    adopted.GetType().GetField("Pid",Private).SetValue(adopted,original.Pid);Field("original").SetValue(owner,adopted);
    MethodInfo observe=typeof(FixedEffectWorker).GetMethod("ObserveAndWait",Private);Check(observe!=null,"missing actual method");
    // Private synthetic-state sentinel. The real method overwrites this only
    // AFTER its native wait returns. It is not an injected native return value.
    var within=typeof(FixedEffectWorker).GetProperty("WithinDeadline",Private);
    Check(within!=null&&within.GetSetMethod(true)!=null,"missing actual wait state");
    within.GetSetMethod(true).Invoke(owner,new object[]{true});
    var queryBuffer=new StringBuilder(32768);var barrier=new ManualResetEvent(false);var enter=new ManualResetEvent(false);var invoking=new ManualResetEvent(false);
    held=new Mutex(false);completed=new ManualResetEvent(false);Exception failure=null;
    ownerThread=new Thread(()=> {
     bool owns=false;
     try {
      owns=held.WaitOne(0);if(!owns)throw new InvalidOperationException("fixture lock unavailable");
      barrier.Set();if(!enter.WaitOne(10000))throw new InvalidOperationException("entry timeout");invoking.Set();
      observe.Invoke(owner,new object[]{queryBuffer,image,(uint)0});
     }catch(Exception e){failure=e;}
     finally {if(owns)held.ReleaseMutex();completed.Set();}
    });
    ownerThread.IsBackground=true;ownerThread.Start();Check(barrier.WaitOne(10000),"entry barrier missing");
    Retained(held,ownerThread,completed,owner);
    Live(original.Process,"production-entry");
    enter.Set();Check(invoking.WaitOne(10000),"owner entry missing");
    var watch=Stopwatch.StartNew();bool sleeping=false;
    while(watch.ElapsedMilliseconds<10000) {
     if(completed.WaitOne(0))throw new InvalidOperationException("production wait did not retain",failure);
     Thread.MemoryBarrier();
     sleeping=!(bool)within.GetValue(owner,null)&&(ownerThread.ThreadState&System.Threading.ThreadState.WaitSleepJoin)!=0;
     if(sleeping)break;Thread.Sleep(10);
    }
    Check(sleeping,"production query/retention not observed");
    Check(String.Equals(queryBuffer.ToString(),image,StringComparison.OrdinalIgnoreCase),"production image query mismatch");
    Check(Field("observationFailure").GetValue(owner)==null,"production image query failed");
    Live(original.Process,"retention-observed");
    Retained(held,ownerThread,completed,owner);
    for(int i=0;i<3;i++) {
     ownerThread.Interrupt(); // Thread.Interrupt must not unwind retained ownership.
     Check(!completed.WaitOne(150),"interruption released owner");Retained(held,ownerThread,completed,owner);
     Live(original.Process,"after-interrupt-"+i);
    }
    if(fault=="--fail-after-retention"){injected=true;throw new InvalidOperationException("EXPECTED retained assertion");}
    NaturalExit(original,release,ref childExited);
    uint code;ok=GetExitCodeProcess(original.Process,out code);int codeError=ok?0:Marshal.GetLastWin32Error();Native(ok,codeError,"natural child exit code");
    Check(code==23,"child did not exit via parent release");
    Retained(held,ownerThread,completed,owner);
    Check(failure==null,"owner exception");
    Console.WriteLine("ACQUIRED_CHILD_RETENTION_PASS assertions="+assertions+" child_exit=23 natural_exit=true owner_returned=false mutex_released=false synthetic_adoption=true production_return_instrumented=false");
    result=0;
   } catch(Exception e) {
    if(injected)Console.WriteLine("ACQUIRED_CHILD_INJECTED_ASSERTION mode="+fault);
    else Console.Error.WriteLine("ACQUIRED_CHILD_RETENTION_FAIL "+e);
   }
   finally {
    if(entered&&!returned)Unknown("create_completion_unknown");
    if(created&&!childExited)NaturalExit(original,release,ref childExited);
    if(created&&childExited) {
     uint finalCode=0;bool known=false;
     try {known=GetExitCodeProcess(original.Process,out finalCode);}catch { }
     releaseExitVerified=known&&finalCode==23;
     if(!releaseExitVerified)result=1;
    }
    // The restricted duplicate stays open/rooted in the retained synthetic owner
    // until this harmless fixture itself exits. Never close a pending owner's handle.
    if(!created||childExited) {
     CloseOriginal(ref original.Thread);CloseOriginal(ref original.Process);
     if(ready!=null)ready.Dispose();if(release!=null)release.Dispose();
    }
   }
   if(injected&&releaseExitVerified)
    Console.WriteLine("ACQUIRED_CHILD_EXPECTED_FAILURE mode="+fault+" child_exit=23 natural_exit=true");
   Console.Out.Flush();Console.Error.Flush();
   // Only after definite absence/no creation or verified natural child exit.
   // This exits our test host, not an effect worker, and is not a recovery action.
   Environment.Exit(result);return result;
  }
 }
}
