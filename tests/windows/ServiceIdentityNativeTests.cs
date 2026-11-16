// TEST-ONLY disposable-host SCM characterization. No VBox, driver or process start.
// This draft is NOT native evidence until explicitly run in authorized Windows CI.
using System;
using System.ComponentModel;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
namespace PortableVBox.ServiceIdentityModel {
 public static class ServiceIdentityNativeTests {
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenSCManager(string machine,string database,uint access);
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenService(IntPtr scm,string name,uint access);
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateService(IntPtr scm,string name,string display,uint access,uint type,uint start,uint error,string binary,string group,IntPtr tag,string dependencies,string account,string password);
  [DllImport("advapi32.dll",SetLastError=true)] static extern bool QueryServiceStatusEx(IntPtr service,int level,out Status status,uint size,out uint needed);
  [DllImport("advapi32.dll",SetLastError=true)] static extern bool DeleteService(IntPtr service);
  [DllImport("advapi32.dll",SetLastError=true)] static extern bool CloseServiceHandle(IntPtr service);
  [StructLayout(LayoutKind.Sequential)] struct Status {internal uint Type,State,Controls,Win32Exit,SpecificExit,Checkpoint,WaitHint,Pid,Flags;}
  static int checks;
  static void Check(bool condition,string label){checks++;if(!condition)throw new Exception(label);}
  sealed class Owned {
   IntPtr handle;bool deleteAttempted,closed;
   internal Owned(IntPtr created){if(created==IntPtr.Zero)throw new ArgumentException();handle=created;}
   internal uint Query(){if(closed)throw new InvalidOperationException("Terminal capability");Status status;uint bytes;if(!QueryServiceStatusEx(handle,0,out status,(uint)Marshal.SizeOf(typeof(Status)),out bytes))throw new Win32Exception(Marshal.GetLastWin32Error());return status.State;}
   internal void Mark(){if(closed||deleteAttempted)throw new InvalidOperationException("One-shot delete");deleteAttempted=true;if(!DeleteService(handle))throw new Win32Exception(Marshal.GetLastWin32Error());}
   internal void Close(){if(closed)return;closed=true;IntPtr h=handle;handle=IntPtr.Zero;if(!CloseServiceHandle(h))throw new Win32Exception(Marshal.GetLastWin32Error());}
   internal void Cleanup(List<Exception> failures,string label){
    try{if(!deleteAttempted&&!closed)Mark();}catch(Exception error){failures.Add(new InvalidOperationException(label+" cleanup delete failed",error));}
    try{Close();}catch(Exception error){failures.Add(new InvalidOperationException(label+" cleanup close failed",error));}
   }
  }
  static IntPtr Create(IntPtr scm,string name){return CreateService(scm,name,name,0x10004,0x10,3,1,"\""+System.IO.Path.Combine(Environment.SystemDirectory,name+"-never-executed.exe")+"\"",null,IntPtr.Zero,null,null,null);}
  // A name-based read-only absence probe is not acquisition of mutation authority.
  // Even an unexpected open handle must never be passed to DeleteService.
  static void RequireAbsent(IntPtr scm,string name){
   var timer=Stopwatch.StartNew();
   while(true){
    IntPtr observed=OpenService(scm,name,4);int error=Marshal.GetLastWin32Error();
    if(observed!=IntPtr.Zero){
     var unexpected=new InvalidOperationException("Final absence UNKNOWN: service unexpectedly opens; never adopt");
     if(!CloseServiceHandle(observed))throw new AggregateException(unexpected,new Win32Exception(Marshal.GetLastWin32Error(),"Read-only observation handle close failed"));
     throw unexpected;
    }
    if(error==1060){Console.WriteLine("SERVICE_IDENTITY_FINAL_ABSENCE error="+error);Check(true,"final fixture name absent");return;}
    if(error!=1072||timer.ElapsedMilliseconds>=5000)throw new Win32Exception(error,"Final absence UNKNOWN; delete pending wait bounded");
    Thread.Sleep(20);
   }
  }
  public static int Main(string[] args){
   if(args.Length!=1||args[0]!="--disposable-scm-identity"||Environment.OSVersion.Platform!=PlatformID.Win32NT||Environment.GetEnvironmentVariable("GITHUB_ACTIONS")!="true"||Environment.GetEnvironmentVariable("GITHUB_REPOSITORY")!="zlocorp/Portable-VirtualBox"||Environment.GetEnvironmentVariable("RUNNER_ENVIRONMENT")!="github-hosted"||Environment.GetEnvironmentVariable("RUNNER_OS")!="Windows")throw new InvalidOperationException("Authorized disposable Windows CI only");
   string name="pvbox-test-"+Guid.NewGuid().ToString("N");IntPtr scm=OpenSCManager(null,null,3);if(scm==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error());
   Owned first=null,second=null;var failures=new List<Exception>();
   try{
    IntPtr initial=Create(scm,name);if(initial==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error(),"Collision/error: refuse adoption and cleanup by name");first=new Owned(initial);
    Check(first.Query()==1,"new fixture service stopped");first.Mark();
    IntPtr blocked=Create(scm,name);int error=Marshal.GetLastWin32Error();
    Console.WriteLine("SERVICE_IDENTITY_RECREATE_OBSERVATION error="+error+" created="+(blocked!=IntPtr.Zero));
    if(blocked!=IntPtr.Zero){second=new Owned(blocked);throw new Exception("Replacement created while original handle retained");}
    Check(error==1072,"delete-pending record blocks recreation");
    first.Close();bool terminal=false;try{first.Query();}catch(InvalidOperationException){terminal=true;}Check(terminal,"closed old capability terminal");
    var timer=Stopwatch.StartNew();
    while(second==null){IntPtr next=Create(scm,name);error=Marshal.GetLastWin32Error();if(next!=IntPtr.Zero){second=new Owned(next);break;}if(error!=1072||timer.ElapsedMilliseconds>5000)throw new Win32Exception(error,"Recreation not observed within bounded fixture");Thread.Sleep(20);}
    Check(second.Query()==1,"new generation stopped");terminal=false;try{first.Query();}catch(InvalidOperationException){terminal=true;}Check(terminal,"old capability cannot address new generation");
    second.Mark();second.Close();RequireAbsent(scm,name);
   }catch(Exception error){failures.Add(error);}
   finally{
    if(second!=null)second.Cleanup(failures,"second generation");
    if(first!=null)first.Cleanup(failures,"first generation");
    if(!CloseServiceHandle(scm))failures.Add(new Win32Exception(Marshal.GetLastWin32Error(),"SCM close failed"));
   }
   if(failures.Count!=0)throw new AggregateException("Service identity fixture failed; original and cleanup failures preserved",failures);
   Console.WriteLine("SERVICE_IDENTITY_NATIVE_PASS checks="+checks+" service_started=false production_authority=false");return 0;
  }
 }
}
