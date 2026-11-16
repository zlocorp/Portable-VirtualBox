// TEST ONLY. Compiled exclusively with the reversible temporary owner source.
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
namespace PortableVBox {
 internal sealed partial class FixedEffectWorker {
  internal static string FaultMode;
  internal static IntPtr FaultOriginalProcess,FaultOriginalThread,FaultObserver;
  internal static IntPtr FaultInjectedProcess,FaultInjectedThread;
  internal static uint FaultOriginalPid,FaultOriginalTid;
  internal static int FaultCreateEntered,FaultCreateReturned,FaultCreated,FaultBoundaryComplete;
  internal static int FaultInjected,FaultWaitCalls,FaultExitQueries,FaultOriginalCloses,FaultCreateAttempts;
  internal static uint FaultRealWaitProbe;
  internal static int FaultDuplicateError,FaultObserverReady;
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool DuplicateHandle(IntPtr sourceProcess,IntPtr source,IntPtr targetProcess,out IntPtr target,uint access,[MarshalAs(UnmanagedType.Bool)] bool inherit,uint options);
  static bool CreateProcessW(string application,StringBuilder command,IntPtr processSecurity,IntPtr threadSecurity,
   bool inherit,uint flags,IntPtr environment,string directory,ref ExtendedStartup startup,out ProcessInformation process){
   // A second attempted create is counted/rejected, never silently replayed.
   if(Interlocked.Increment(ref FaultCreateAttempts)!=1)throw new InvalidOperationException("Test boundary repeated create");
   Volatile.Write(ref FaultCreateEntered,1);
   bool result=FaultNativeCreateProcessW(application,command,processSecurity,threadSecurity,inherit,flags,environment,directory,ref startup,out process);
   // Store true kernel observations before any synthetic result or diagnostics.
   FaultOriginalProcess=process.Process;FaultOriginalThread=process.Thread;FaultOriginalPid=process.Pid;FaultOriginalTid=process.Tid;
   Volatile.Write(ref FaultCreated,result?1:0);Volatile.Write(ref FaultCreateReturned,1);
   if(result&&Valid(process.Process)&&Valid(process.Thread)&&process.Process!=process.Thread){
    bool duplicated=DuplicateHandle(GetCurrentProcess(),process.Process,GetCurrentProcess(),out FaultObserver,0x00101000,false,0);
    FaultDuplicateError=duplicated?0:Marshal.GetLastWin32Error();
    if(!duplicated||!Valid(FaultObserver)||FaultObserver==process.Process||FaultObserver==process.Thread) {Volatile.Write(ref FaultBoundaryComplete,1);throw new InvalidOperationException("Test observer acquisition failed");}
    Volatile.Write(ref FaultObserverReady,1);
   }
   Volatile.Write(ref FaultBoundaryComplete,1);
   if(result&&FaultMode=="true-aliased-outputs") {
    // Preserve genuine outputs/observer above; alter only the owner's returned Thread.
    process.Thread=process.Process;
    FaultInjectedProcess=process.Process;FaultInjectedThread=process.Thread;
    Volatile.Write(ref FaultInjected,1);return true;
   }
   if(result&&FaultMode=="false-outputs") {Volatile.Write(ref FaultInjected,1);return false;}
   return result;
  }
  static uint WaitForSingleObject(IntPtr handle,uint milliseconds){
   Interlocked.Increment(ref FaultWaitCalls);
   if(FaultMode=="wait-failed"&&handle==FaultOriginalProcess&&Volatile.Read(ref FaultCreated)==1){
    FaultRealWaitProbe=FaultNativeWaitForSingleObject(handle,0);
    if(FaultRealWaitProbe!=258)throw new InvalidOperationException("Test wait injection requires live original");
    Volatile.Write(ref FaultInjected,1);return 0xffffffff;
   }
   return FaultNativeWaitForSingleObject(handle,milliseconds);
  }
  static bool GetExitCodeProcess(IntPtr process,out uint code){
   Interlocked.Increment(ref FaultExitQueries);return FaultNativeGetExitCodeProcess(process,out code);
  }
  static bool CloseHandle(IntPtr handle){
   if(handle!=IntPtr.Zero&&(handle==FaultOriginalProcess||handle==FaultOriginalThread))Interlocked.Increment(ref FaultOriginalCloses);
   return FaultNativeCloseHandle(handle);
  }
 }
}
