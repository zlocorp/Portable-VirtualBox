// Closed production adapter for the already verified, built-in PowerShell worker.
// No executable/argument selector is exposed to the frontend. Never terminate a
// worker or abandon its lifetime because capture, diagnostics or waiting failed.
using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;
namespace PortableVBox {
 internal sealed class FixedEffectWorker : IDisposable {
  [StructLayout(LayoutKind.Sequential)] struct Security { internal int Length;internal IntPtr Descriptor;internal int Inherit; }
  [StructLayout(LayoutKind.Sequential)] struct Startup {
   internal int Size;internal IntPtr Reserved,Desktop,Title;
   internal uint X,Y,XSize,YSize,XChars,YChars,Fill,Flags;
   internal ushort Show,ReservedSize;internal IntPtr ReservedBytes,Input,Output,Error;
  }
  [StructLayout(LayoutKind.Sequential)] struct ExtendedStartup { internal Startup Startup;internal IntPtr Attributes; }
  [StructLayout(LayoutKind.Sequential)] struct ProcessInformation { internal IntPtr Process,Thread;internal uint Pid,Tid; }
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool CreatePipe(out IntPtr read,out IntPtr write,ref Security security,uint size);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool SetHandleInformation(IntPtr handle,uint mask,uint flags);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true,ExactSpelling=true)]
  static extern IntPtr CreateFileW(string name,uint access,uint share,ref Security security,uint creation,uint flags,IntPtr template);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool InitializeProcThreadAttributeList(IntPtr list,int count,uint flags,ref IntPtr bytes);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool UpdateProcThreadAttribute(IntPtr list,uint flags,IntPtr attribute,IntPtr value,IntPtr size,IntPtr previous,IntPtr returned);
  [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,ExactSpelling=true,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool CreateProcessW(string application,StringBuilder command,IntPtr processSecurity,IntPtr threadSecurity,
   [MarshalAs(UnmanagedType.Bool)] bool inherit,uint flags,IntPtr environment,string directory,ref ExtendedStartup startup,out ProcessInformation process);
  [DllImport("kernel32.dll",SetLastError=true)] static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] static extern bool GetExitCodeProcess(IntPtr process,out uint code);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,ExactSpelling=true,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool QueryFullProcessImageNameW(IntPtr process,uint flags,StringBuilder name,ref uint length);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] static extern bool CloseHandle(IntPtr handle);

  // Readers and their threads are fully constructed and started before Create.
  // An output accumulation fault switches to discard/drain, never stops the other
  // reader. Failure is returned separately; partial output never counts as success.
  sealed class Reader {
   internal readonly StreamReader Stream;
   internal readonly Thread Thread;
   readonly StringBuilder text=new StringBuilder();
   readonly char[] buffer=new char[4096];
   internal Exception Failure;
   internal bool Eof;
   internal readonly TaskCompletionSource<string> Completion=new TaskCompletionSource<string>();
   internal Reader(IntPtr handle,Encoding encoding):this(new StreamReader(new FileStream(new SafeFileHandle(handle,false),FileAccess.Read,4096,false),encoding,true,4096)) { }
   // Private managed seam exercises this exact reader without native handles.
   internal Reader(StreamReader stream) {
    if(stream==null)throw new ArgumentNullException("stream");
    Stream=stream;Thread=new Thread(Read);Thread.IsBackground=false;
   }
   void Read() {
    try {
     for(;;) {
      int count=Stream.Read(buffer,0,buffer.Length);
      if(count==0) {Eof=true;break;}
      if(Failure==null) try {text.Append(buffer,0,count);} catch(Exception error) {Failure=error;}
     }
    } catch(Exception error) {if(Failure==null)Failure=error;}
    finally {try {Stream.Dispose();} catch(Exception error) {if(Failure==null)Failure=error;}}
    // Failure is observable, but EOF remains a separate ownership fact. A faulted
    // task cannot authorize disposal of the raw pipe or Main's global locks.
    try {
     if(Failure!=null)Completion.TrySetException(Failure);
     else if(Eof)Completion.TrySetResult(text.ToString());
     else Completion.TrySetException(new IOException("Worker capture did not reach EOF"));
    } catch(Exception error) {
     try {Completion.TrySetException(error);} catch {for(;;) {try {Thread.Sleep(1000);} catch(ThreadInterruptedException) { }}}
    }
   }
  }
  ProcessInformation original; // Rooted before the native create call writes it.
  IntPtr stdoutRead,stdoutWrite,stderrRead,stderrWrite,input,attributes,handleList,environment;
  bool attributesReady,createEntered,createReturned,created,exited,finished,disposed;
  Reader stdout,stderr;
  bool stdoutStartEntered,stderrStartEntered;
  bool stdoutOwned,stdoutWriterOwned,stderrOwned,stderrWriterOwned,inputOwned,originalsOwned;
  bool preparationUnknown;
  FileStream imageLease;
  Exception observationFailure;
  readonly Exception invalidExitCode=new InvalidOperationException("Fixed worker exit code observation failed");
  readonly Exception invalidImage=new InvalidOperationException("Fixed worker image observation failed");
  internal bool WithinDeadline {get;private set;}
  internal int ExitCode {get;private set;}
  internal bool ExitCodeKnown {get;private set;}
  internal Task<string> StandardOutput {get;private set;}
  internal Task<string> StandardError {get;private set;}
  FixedEffectWorker() { }
  static bool Valid(IntPtr handle) {return handle!=IntPtr.Zero && handle!=new IntPtr(-1);}
  static void Check(bool ok,string message) {if(!ok)throw new Win32Exception(Marshal.GetLastWin32Error(),message);}
  static void CloseKnown(ref IntPtr handle) {
   if(!Valid(handle))return;
   IntPtr current=handle;
   // Never retry a possibly recycled handle after a failed/unavailable close.
   handle=IntPtr.Zero;
   if(!CloseHandle(current))throw new Win32Exception(Marshal.GetLastWin32Error(),"Worker handle close failed");
  }
  // Unknown acquisition or wait cannot unwind into Main's lock-release finally.
  // Keep this owner and its fields rooted, with no relaunch/cleanup/kill attempt.
  void RetainUnknown() {
   for(;;) {
    try {Thread.Sleep(1000);} catch(ThreadInterruptedException) { }
    GC.KeepAlive(this);
   }
  }
  static bool ReleaseAllowed(bool entered,bool returned,bool childCreated,bool childExited,bool stdoutEof,bool stderrEof) {
   return (!entered||returned) && (!childCreated||(childExited&&stdoutEof&&stderrEof));
  }
  bool ReleaseAllowed() {
   return ReleaseAllowed(createEntered,createReturned,created,exited,stdout!=null&&stdout.Eof,stderr!=null&&stderr.Eof);
  }
  static string BuildEnvironment(ProcessStartInfo info) {
   var allowed=new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
    "SystemRoot","WINDIR","PATH","ProgramFiles","ProgramData","TEMP","TMP","PSModulePath",
    "GITHUB_ACTIONS","GITHUB_REPOSITORY","RUNNER_ENVIRONMENT","RUNNER_OS","GITHUB_SHA","PVBOX_FIXED_HELPER_MODE","RUNNER_TEMP"
   };
   var entries=new SortedDictionary<string,string>(StringComparer.OrdinalIgnoreCase);
   foreach(DictionaryEntry entry in info.EnvironmentVariables) {
    string key=(string)entry.Key,value=(string)entry.Value;
    if(!allowed.Contains(key)||key.IndexOf('=')>=0||key.IndexOf('\0')>=0||value==null||value.IndexOf('\0')>=0)
     throw new InvalidOperationException("Invalid fixed worker environment");
    entries.Add(key,value);
   }
   var block=new StringBuilder();
   foreach(var entry in entries)block.Append(entry.Key).Append('=').Append(entry.Value).Append('\0');
   block.Append('\0');return block.ToString();
  }
  void Prepare(ProcessStartInfo info,string image,bool inheritEnvironment) {
   if(!info.RedirectStandardOutput||!info.RedirectStandardError||info.UseShellExecute||!info.CreateNoWindow)
    throw new InvalidOperationException("Invalid fixed worker transport policy");
   imageLease=new FileStream(image,FileMode.Open,FileAccess.Read,FileShare.Read);
   var security=new Security {Length=Marshal.SizeOf(typeof(Security)),Inherit=1};
   bool stdoutCreated=CreatePipe(out stdoutRead,out stdoutWrite,ref security,0);
   int stdoutError=stdoutCreated?0:Marshal.GetLastWin32Error();
   if(!stdoutCreated) {
    if(stdoutRead!=IntPtr.Zero||stdoutWrite!=IntPtr.Zero){preparationUnknown=true;RetainUnknown();}
    throw new Win32Exception(stdoutError,"Create worker stdout");
   }
   if(!Valid(stdoutRead)||!Valid(stdoutWrite)||stdoutRead==stdoutWrite){preparationUnknown=true;RetainUnknown();}
   stdoutOwned=true;stdoutWriterOwned=true;
   Check(SetHandleInformation(stdoutRead,1,0),"Exclude stdout reader from inheritance");
   bool stderrCreated=CreatePipe(out stderrRead,out stderrWrite,ref security,0);
   int stderrError=stderrCreated?0:Marshal.GetLastWin32Error();
   if(!stderrCreated) {
    if(stderrRead!=IntPtr.Zero||stderrWrite!=IntPtr.Zero){preparationUnknown=true;RetainUnknown();}
    throw new Win32Exception(stderrError,"Create worker stderr");
   }
   if(!Valid(stderrRead)||!Valid(stderrWrite)||stderrRead==stderrWrite){preparationUnknown=true;RetainUnknown();}
   stderrOwned=true;stderrWriterOwned=true;
   Check(SetHandleInformation(stderrRead,1,0),"Exclude stderr reader from inheritance");
   input=CreateFileW("NUL",0x80000000,3,ref security,3,0,IntPtr.Zero);
   if(!Valid(input))throw new Win32Exception(Marshal.GetLastWin32Error(),"Open worker stdin");
   inputOwned=true;
   IntPtr bytes=IntPtr.Zero;
   bool initial=InitializeProcThreadAttributeList(IntPtr.Zero,1,0,ref bytes);
   int initialError=Marshal.GetLastWin32Error();
   if(initial||initialError!=122||bytes.ToInt64()<=0||bytes.ToInt64()>1048576)
    throw new InvalidOperationException("Invalid process attribute allocation");
   attributes=Marshal.AllocHGlobal(bytes);
   Check(InitializeProcThreadAttributeList(attributes,1,0,ref bytes),"Initialize worker inheritance");attributesReady=true;
   handleList=Marshal.AllocHGlobal(3*IntPtr.Size);
   Marshal.WriteIntPtr(handleList,0,input);Marshal.WriteIntPtr(handleList,IntPtr.Size,stdoutWrite);Marshal.WriteIntPtr(handleList,2*IntPtr.Size,stderrWrite);
   Check(UpdateProcThreadAttribute(attributes,0,new IntPtr(0x20002),handleList,new IntPtr(3*IntPtr.Size),IntPtr.Zero,IntPtr.Zero),"Pin worker inherited handles");
   if(!inheritEnvironment)environment=Marshal.StringToHGlobalUni(BuildEnvironment(info));
   Encoding encoding=Console.OutputEncoding;
   stdout=new Reader(stdoutRead,encoding);
   stderr=new Reader(stderrRead,encoding);
   StandardOutput=stdout.Completion.Task;StandardError=stderr.Completion.Task;
   stdoutStartEntered=true;stdout.Thread.Start();
   stderrStartEntered=true;stderr.Thread.Start();
  }
  void CloseParentWriters() {
   Exception error=null;
   try {if(stdoutWriterOwned){stdoutWriterOwned=false;CloseKnown(ref stdoutWrite);}}catch(Exception e){error=e;}
   try {if(stderrWriterOwned){stderrWriterOwned=false;CloseKnown(ref stderrWrite);}}catch(Exception e){if(error==null)error=e;}
   try {if(inputOwned){inputOwned=false;CloseKnown(ref input);}}catch(Exception e){if(error==null)error=e;}
   if(error!=null)RetainUnknown();
  }
  void JoinReader(Reader reader,bool startEntered) {
   if(reader==null)return;
   if(!startEntered || (reader.Thread.ThreadState&System.Threading.ThreadState.Unstarted)!=0)reader.Stream.Dispose();
   else {
    // Interruption is not evidence of EOF and must not escape to Main finally.
    for(;;) {
     try {reader.Thread.Join();break;}
     catch(ThreadInterruptedException) { }
     catch {RetainUnknown();}
    }
   }
  }
  void FinishCapture() {
   // Closing parent writers lets readers see EOF once all actual child writers
   // have closed. Joins preserve descendant-held output lifetime after worker exit.
   CloseParentWriters();
   JoinReader(stdout,stdoutStartEntered);JoinReader(stderr,stderrStartEntered);
   // A joined reader may have faulted before EOF. That is not complete capture,
   // and must not unwind into Main's global lock-release finally.
   if(created && (!stdout.Eof||!stderr.Eof))RetainUnknown();
  }
  internal void VerifyImageObservation() {if(observationFailure!=null)throw observationFailure;}
  void ObserveAndWait(StringBuilder observed,string image,uint deadline) {
   try {
    uint size=(uint)observed.Capacity;
    bool queried=QueryFullProcessImageNameW(original.Process,0,observed,ref size);
    if(!queried||!String.Equals(observed.ToString(),image,StringComparison.OrdinalIgnoreCase))observationFailure=invalidImage;
   } catch {observationFailure=invalidImage;}
   uint wait=WaitForSingleObject(original.Process,deadline);
   WithinDeadline=wait==0;
   if(wait==258)wait=WaitForSingleObject(original.Process,0xffffffff);
   if(wait!=0)RetainUnknown();
   exited=true;
   // A signalled original handle proves exit even when its code cannot be read.
   // Preserve that fact for the journal, then reject success at the observation gate.
   ExitCode=-1;
   try {
    uint code;
    if(GetExitCodeProcess(original.Process,out code)) {ExitCode=unchecked((int)code);ExitCodeKnown=true;}
    else observationFailure=invalidExitCode;
   } catch {observationFailure=invalidExitCode;}
  }
  internal static FixedEffectWorker Run(ProcessStartInfo info) {
   string image=Path.Combine(Environment.SystemDirectory,"WindowsPowerShell","v1.0","powershell.exe");
   if(info==null||!String.Equals(info.FileName,image,StringComparison.OrdinalIgnoreCase)||image.IndexOf('"')>=0)
    throw new InvalidOperationException("Only built-in Windows PowerShell may execute");
   return RunCore(info,image,150000,false);
  }
  // The protected SDS facade admits the pinned Oracle image and fixes all paths.
  // This internal wrapper cannot select arbitrary executable names or arguments.
  internal static FixedEffectWorker RunSds(string image,bool unregister,int timeoutSeconds) {
   if(String.IsNullOrEmpty(image)||!Path.IsPathRooted(image)||
      !String.Equals(Path.GetFileName(image),"VBoxSDS.exe",StringComparison.OrdinalIgnoreCase)||
      image.IndexOf('"')>=0||timeoutSeconds<5||timeoutSeconds>90)
    throw new InvalidOperationException("Invalid fixed SDS image/deadline");
   var info=new ProcessStartInfo(image,unregister?"--unregservice":"--regservice");
   info.WorkingDirectory=Path.GetDirectoryName(image);info.UseShellExecute=false;
   info.CreateNoWindow=true;info.RedirectStandardOutput=true;info.RedirectStandardError=true;
   // SDS inherits the existing protected PowerShell environment, as before.
   // A null native environment pointer preserves it without a caller selector.
   return RunCore(info,image,checked((uint)timeoutSeconds*1000),true);
  }
  static FixedEffectWorker RunCore(ProcessStartInfo info,string image,uint deadline,bool inheritEnvironment) {
   var owner=new FixedEffectWorker();
   var command=new StringBuilder("\""+image+"\" "+info.Arguments);
   var observed=new StringBuilder(32768);
   try {
    owner.Prepare(info,image,inheritEnvironment);
    var startup=new ExtendedStartup();startup.Startup.Size=Marshal.SizeOf(typeof(ExtendedStartup));startup.Startup.Flags=0x100;
    startup.Startup.Input=owner.input;startup.Startup.Output=owner.stdoutWrite;startup.Startup.Error=owner.stderrWrite;startup.Attributes=owner.attributes;
    owner.createEntered=true;
    bool result=CreateProcessW(image,command,IntPtr.Zero,IntPtr.Zero,true,0x08080400,owner.environment,info.WorkingDirectory,ref startup,out owner.original);
    // No stream construction, diagnostic allocation or callback before storage.
    owner.created=result;owner.createReturned=true;
    int createError=result?0:Marshal.GetLastWin32Error();
    if(!result) {
     if(owner.original.Process!=IntPtr.Zero||owner.original.Thread!=IntPtr.Zero||owner.original.Pid!=0||owner.original.Tid!=0)owner.RetainUnknown();
     throw new Win32Exception(createError,"Fixed worker creation failed");
    }
    if(!Valid(owner.original.Process)||!Valid(owner.original.Thread)||owner.original.Process==owner.original.Thread)owner.RetainUnknown();
    owner.originalsOwned=true;
    owner.CloseParentWriters();
    owner.ObserveAndWait(observed,image,deadline);
    // Return measured exit before waiting for inherited descendant writers or
    // string materialization. Main persists WorkerExited before awaiting Tasks.
    return owner;
   } catch {
    if(owner.preparationUnknown || owner.createEntered&&!owner.createReturned)owner.RetainUnknown();
    if(owner.created&&!owner.exited) {
     uint wait=WaitForSingleObject(owner.original.Process,0xffffffff);
     if(wait!=0)owner.RetainUnknown();
     owner.exited=true;
    }
    if(!owner.finished) {owner.FinishCapture();owner.finished=true;}
    owner.Dispose();throw;
   }
  }
  public void Dispose() {
   if(disposed)return;
   if(preparationUnknown || createEntered&&!createReturned || created&&!exited)RetainUnknown();
   if(!finished){FinishCapture();finished=true;}
   if(!ReleaseAllowed())RetainUnknown();
   disposed=true;
   if(originalsOwned){originalsOwned=false;CloseKnown(ref original.Thread);CloseKnown(ref original.Process);}
   if(stdoutOwned){stdoutOwned=false;CloseKnown(ref stdoutRead);}
   if(stderrOwned){stderrOwned=false;CloseKnown(ref stderrRead);}
   if(attributesReady){DeleteProcThreadAttributeList(attributes);attributesReady=false;}
   if(attributes!=IntPtr.Zero)Marshal.FreeHGlobal(attributes);
   if(handleList!=IntPtr.Zero)Marshal.FreeHGlobal(handleList);
   if(environment!=IntPtr.Zero)Marshal.FreeHGlobal(environment);
   if(imageLease!=null)imageLease.Dispose();
  }
 }
}
