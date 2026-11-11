// TEST ONLY. Fixed sibling image, original handles, bounded exact-slot capture.
using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
namespace PortableVBox {
 internal static class EnvironmentEvidenceSink {
  internal static bool TryWrite(System.IO.Stream sink) { int written;return TryWriteCounted(sink,out written); }
  internal static bool TryWriteCounted(System.IO.Stream sink,out int written) {
   written=0;
   try { sink.WriteByte(0);written=1;sink.Flush();throw new IOException("Controlled environment diagnostic fault"); }
   catch { return false; }
  }
 }
 internal enum CaptureCase { Empty,Binary,Large,Nonzero,Exit259,PostCreateFault,CaptureFault,EvidenceFault,WithheldEof,EnvironmentObservation }
 internal enum EnvironmentObservationFault { None,AfterCreate,Evidence }
 internal static class ChildCaptureApi {
  [StructLayout(LayoutKind.Sequential)] internal struct Startup {
   internal int Size;
   internal IntPtr Reserved,Desktop,Title;
   internal uint X,Y,XSize,YSize,XChars,YChars,Fill,Flags;
   internal ushort Show,ReservedSize;
   internal IntPtr ReservedBytes,Input,Output,Error;
  }
  [StructLayout(LayoutKind.Sequential)] internal struct ExtendedStartup { internal Startup Startup;internal IntPtr Attributes; }
  [StructLayout(LayoutKind.Sequential)] internal struct ProcessInfo { internal IntPtr Process,Thread;internal uint Pid,Tid; }
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,ExactSpelling=true,SetLastError=true)]
  [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool CreateProcessW(string image,StringBuilder command,IntPtr processSecurity,
   IntPtr threadSecurity,[MarshalAs(UnmanagedType.Bool)] bool inherit,uint flags,IntPtr environment,string directory,
   ref ExtendedStartup startup,out ProcessInfo information);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  internal static extern bool InitializeProcThreadAttributeList(IntPtr list,int count,uint flags,ref IntPtr size);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  internal static extern bool UpdateProcThreadAttribute(IntPtr list,uint flags,IntPtr attribute,IntPtr value,IntPtr size,IntPtr previous,IntPtr returned);
  [DllImport("kernel32.dll")] internal static extern void DeleteProcThreadAttributeList(IntPtr list);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  internal static extern bool SetHandleInformation(IntPtr handle,uint mask,uint flags);
  [DllImport("kernel32.dll",SetLastError=true)] internal static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  internal static extern bool GetExitCodeProcess(IntPtr handle,out uint code);
 }
 internal sealed class ChildCaptureChannel {
  internal readonly PipeNativeSlot Connect=new PipeNativeSlot(),Read=new PipeNativeSlot();
  internal readonly PipeCapture Capture=new PipeCapture();
  internal readonly PipeCloseProof ServerClose=new PipeCloseProof(),WriterClose=new PipeCloseProof();
  internal IntPtr Server,Writer;
  internal int Visits,PreviousVisit,MaxGap;
  internal bool Stopped;
 }
 internal sealed class ChildCaptureOwner {
  internal readonly ChildCaptureProof Proof=new ChildCaptureProof();
  internal readonly ChildCaptureChannel[] Channels={new ChildCaptureChannel(),new ChildCaptureChannel()};
  internal readonly CaptureCase Scenario;
  // PROCESS_INFORMATION is itself rooted BEFORE entering CreateProcessW.
  internal ChildCaptureApi.ProcessInfo Original;
  readonly PipeNativeSlot[] slots=new PipeNativeSlot[4];
  readonly PipeCloseProof inputClose=new PipeCloseProof(),sentinelClose=new PipeCloseProof(),heldClose=new PipeCloseProof(),
   processClose=new PipeCloseProof(),threadClose=new PipeCloseProof();
  readonly FixedChildEnvironment environment;
  readonly EnvironmentAllocation environmentAllocation=new EnvironmentAllocation();
  readonly EnvironmentObservationFault environmentFault;
  CreateEntryState createState;
  internal string ExpectedWindowsDirectory { get { return environment==null?null:environment.WindowsDirectory; } }
  internal CreateEntryState CreateState { get { return createState; } }
  internal bool EnvironmentReleased { get { return environment==null || environmentAllocation.Released; } }
  readonly IFreshSentinelNativeCalls sentinelCalls=new SentinelNativeCalls();
  readonly string sentinelToken=Guid.NewGuid().ToString("N");
  bool sentinelPreparationEntered;
  uint? sentinelCreateError,sentinelFlagError,sentinelCloseError;
  SentinelCallOutcome sentinelCreateOutcome,sentinelFlagOutcome,sentinelCloseOutcome;
  internal bool SentinelReady { get; private set; }
  internal SentinelCallOutcome SentinelCreateOutcome { get { return sentinelCreateOutcome; } }
  internal SentinelCallOutcome SentinelFlagOutcome { get { return sentinelFlagOutcome; } }
  internal SentinelCallOutcome SentinelCloseOutcome { get { return sentinelCloseOutcome; } }
  internal uint? SentinelCreateError { get { return sentinelCreateError; } }
  internal uint? SentinelFlagError { get { return sentinelFlagError; } }
  internal uint? SentinelCloseError { get { return sentinelCloseError; } }
  readonly Stopwatch clock=new Stopwatch();
  readonly Exception injected=new IOException("Controlled fixture fault");
  readonly byte[] evidenceBytes=new byte[1];
  IntPtr input,sentinel,held,descriptor,attributes,handleList;
  bool nativeOutcomeUnknown,attributeInitialized,releaseAttempted,used,created,faultInjected;
  FileStream imageLease,evidence;
  internal bool Released,SentinelProbe,SentinelUnsignaled,HeldWriterBlockedEof,OneShotRefused;
  internal int EnvironmentFaultAtBytes;
  internal int Rounds,FaultSite,EvidenceBytesWritten,CreateCalls,WaitCalls,ExitCodeReads;
  internal uint ExitCode,CreateError;
  internal int AssertionFailedAt;
  internal bool Created { get { return created; } }
  internal bool Unknown { get { return Proof.Unknown || nativeOutcomeUnknown || Channels[0].Capture.Unknown || Channels[1].Capture.Unknown; } }
  internal ChildCaptureOwner(CaptureCase scenario):this(scenario,new SentinelNativeCalls()) { }
  internal ChildCaptureOwner(CaptureCase scenario,IFreshSentinelNativeCalls calls) {
   if(scenario<CaptureCase.Empty || scenario>CaptureCase.WithheldEof) throw new ArgumentOutOfRangeException("scenario");
   if(calls==null) throw new ArgumentNullException("calls");
   sentinelCalls=calls;Scenario=scenario;
   for(int i=0;i<2;i++) { slots[i*2]=Channels[i].Connect;slots[i*2+1]=Channels[i].Read; }
  }
  internal ChildCaptureOwner(FixedChildEnvironment policy):this(policy,EnvironmentObservationFault.None) { }
  internal ChildCaptureOwner(FixedChildEnvironment policy,EnvironmentObservationFault fault) {
   if(policy==null) throw new ArgumentNullException("policy");
   if(fault<EnvironmentObservationFault.None || fault>EnvironmentObservationFault.Evidence) throw new ArgumentOutOfRangeException("fault");
   environment=policy;environmentFault=fault;Scenario=CaptureCase.EnvironmentObservation;
   for(int i=0;i<2;i++) { slots[i*2]=Channels[i].Connect;slots[i*2+1]=Channels[i].Read; }
  }
  internal void PrepareFreshSentinel(IntPtr privateDescriptor) {
   if(sentinelPreparationEntered) throw new InvalidOperationException("Fresh sentinel preparation is one-shot");
   sentinelPreparationEntered=true;
   try {
    nativeOutcomeUnknown=true;sentinelCreateOutcome=SentinelCallOutcome.ReturnUnavailable;
    string name=SentinelProtocol.ReferenceName(sentinelToken);
    sentinelCalls.ClearLastError();
    sentinel=sentinelCalls.CreateEvent(privateDescriptor,true,false,false,name);
    // Retain the returned handle before immediately capturing Create's freshness error.
    sentinelCreateError=sentinelCalls.CaptureLastError();
    sentinelCreateOutcome=sentinel==IntPtr.Zero?SentinelCallOutcome.KnownFailure:SentinelCallOutcome.KnownSuccess;
    nativeOutcomeUnknown=false;
    if(sentinel==IntPtr.Zero) throw new InvalidOperationException("Sentinel creation failed");
    if(sentinelCreateError==183) {
     CloseSentinel();
     throw new InvalidOperationException("Fresh sentinel required");
    }
    nativeOutcomeUnknown=true;sentinelFlagOutcome=SentinelCallOutcome.ReturnUnavailable;
    sentinelCalls.ClearLastError();
    bool inherited=sentinelCalls.SetHandleInformation(sentinel,1,1);
    if(!inherited) sentinelFlagError=sentinelCalls.CaptureLastError();
    sentinelFlagOutcome=inherited?SentinelCallOutcome.KnownSuccess:SentinelCallOutcome.KnownFailure;
    nativeOutcomeUnknown=false;
    if(!inherited) {
     CloseSentinel();
     throw new InvalidOperationException("Sentinel inheritance setup failed");
    }
    SentinelReady=true;
   } catch { MarkUnknown();throw; }
  }
  internal void CloseSentinel() {
   SentinelReady=false;
   if(sentinel==IntPtr.Zero || sentinelClose.Attempted || nativeOutcomeUnknown) return;
   sentinelClose.BeforeClose();
   try {
    nativeOutcomeUnknown=true;sentinelCloseOutcome=SentinelCallOutcome.ReturnUnavailable;
    sentinelCalls.ClearLastError();
    bool closed=sentinelCalls.CloseHandle(sentinel);
    if(!closed) sentinelCloseError=sentinelCalls.CaptureLastError();
    sentinelCloseOutcome=closed?SentinelCallOutcome.KnownSuccess:SentinelCallOutcome.KnownFailure;
    sentinelClose.Returned(closed);
    nativeOutcomeUnknown=false;
    if(!closed) throw new InvalidOperationException("Exact sentinel close failed");
    sentinel=IntPtr.Zero;
   } catch { MarkUnknown();throw; }
  }
  void MarkUnknown() { Proof.Fault(); }
  void Close(ref IntPtr handle,PipeCloseProof close) {
   if(handle==IntPtr.Zero) return;
   close.BeforeClose();
   bool result=PipeNative.CloseHandle(handle);
   close.Returned(result);
   if(!result) throw new InvalidOperationException("Exact handle close failed");
   handle=IntPtr.Zero;
  }
  bool CloseUnresolved { get { return inputClose.Unresolved || sentinelClose.Unresolved || heldClose.Unresolved || processClose.Unresolved || threadClose.Unresolved ||
   Channels[0].ServerClose.Unresolved || Channels[0].WriterClose.Unresolved || Channels[1].ServerClose.Unresolved || Channels[1].WriterClose.Unresolved; } }
  bool IoTerminal { get {
   for(int i=0;i<slots.Length;i++) if(!slots[i].Proof.SafeToRelease || slots[i].AllocationUnknown || slots[i].ReleaseUncertain) return false;
   return true;
  } }
  void SetInherit(IntPtr handle) { if(!ChildCaptureApi.SetHandleInformation(handle,1,1)) throw new InvalidOperationException("Inheritance setup failed"); }
  void Prepare() {
   if(IntPtr.Size!=8 || Marshal.SizeOf(typeof(ChildCaptureApi.ExtendedStartup))!=112 || Marshal.SizeOf(typeof(PipeNative.Overlapped))!=32)
    throw new InvalidOperationException("x64 native layouts required");
   if(environment!=null) environmentAllocation.Prepare(environment.CopyBytes());
   for(int i=0;i<slots.Length;i++) slots[i].Allocate();
   string sid;
   using(WindowsIdentity identity=WindowsIdentity.GetCurrent()) sid=identity.User.Value;
   uint size;
   nativeOutcomeUnknown=true;
   bool converted=PipeNative.ConvertStringSecurityDescriptorToSecurityDescriptorW("D:P(A;;GA;;;SY)(A;;GA;;;"+sid+")",1,out descriptor,out size);
   nativeOutcomeUnknown=false;
   if(!converted) throw new InvalidOperationException("Private DACL failed");
   var security=new PipeNative.SecurityAttributes();security.Length=Marshal.SizeOf(typeof(PipeNative.SecurityAttributes));security.Descriptor=descriptor;
   for(int i=0;i<2;i++) {
    ChildCaptureChannel channel=Channels[i];
    string name=@"\\.\pipe\pvbox-fixed-child-"+Guid.NewGuid().ToString("N");
    nativeOutcomeUnknown=true;
    channel.Server=PipeNative.CreateNamedPipeW(name,0x40080001,8,1,4096,4096,0,ref security);
    nativeOutcomeUnknown=false;
    if(channel.Server==PipeNative.Invalid) { channel.Server=IntPtr.Zero;throw new InvalidOperationException("Pipe creation failed"); }
    channel.Connect.Handle=channel.Server;channel.Read.Handle=channel.Server;
    channel.Connect.Submit(0,0);
    nativeOutcomeUnknown=true;
    // No FILE_FLAG_OVERLAPPED: the inherited child endpoint is synchronous.
    channel.Writer=PipeNative.CreateFileW(name,0x40000000,0,IntPtr.Zero,3,0,IntPtr.Zero);
    nativeOutcomeUnknown=false;
    if(channel.Writer==PipeNative.Invalid) { channel.Writer=IntPtr.Zero;throw new InvalidOperationException("Synchronous writer failed"); }
    SetInherit(channel.Writer);
   }
   clock.Restart();
   while(clock.ElapsedMilliseconds<1000) {
    bool done=true;
    for(int i=0;i<2;i++) { Channels[i].Connect.Poll(); if(!Channels[i].Connect.HasResult) done=false; }
    if(done) break;
    System.Threading.Thread.Sleep(1);
   }
   for(int i=0;i<2;i++) {
    if(!Channels[i].Connect.HasResult || Channels[i].Connect.Error!=0) throw new InvalidOperationException("Connection terminal not observed");
    Channels[i].Connect.Consume();
   }
   nativeOutcomeUnknown=true;
   input=PipeNative.CreateFileW("NUL",0x80000000,3,IntPtr.Zero,3,0,IntPtr.Zero);
   nativeOutcomeUnknown=false;
   if(input==PipeNative.Invalid) { input=IntPtr.Zero;throw new InvalidOperationException("Fixed stdin failed"); }
   SetInherit(input);
   PrepareFreshSentinel(descriptor);
   if(Scenario==CaptureCase.WithheldEof) {
    IntPtr self=PipeNative.GetCurrentProcess();
    nativeOutcomeUnknown=true;
    bool duplicated=PipeNative.DuplicateHandle(self,Channels[0].Writer,self,out held,0,false,2);
    nativeOutcomeUnknown=false;
    if(!duplicated) { held=IntPtr.Zero;throw new InvalidOperationException("Duplicate writer failed"); }
   }
   IntPtr length=IntPtr.Zero;
   bool sized=ChildCaptureApi.InitializeProcThreadAttributeList(IntPtr.Zero,1,0,ref length);
   int error=Marshal.GetLastWin32Error();
   if(sized || error!=122 || length.ToInt64()<=0 || length.ToInt64()>65536) throw new InvalidOperationException("Attribute size query failed");
   attributes=Marshal.AllocHGlobal(length);handleList=Marshal.AllocHGlobal(24);
   nativeOutcomeUnknown=true;
   bool initialized=ChildCaptureApi.InitializeProcThreadAttributeList(attributes,1,0,ref length);
   nativeOutcomeUnknown=false;
   if(!initialized) throw new InvalidOperationException("Attribute initialization failed");
   attributeInitialized=true;
   Marshal.WriteIntPtr(handleList,0,input);Marshal.WriteIntPtr(handleList,8,Channels[0].Writer);Marshal.WriteIntPtr(handleList,16,Channels[1].Writer);
   if(!ChildCaptureApi.UpdateProcThreadAttribute(attributes,0,new IntPtr(0x20002),handleList,new IntPtr(24),IntPtr.Zero,IntPtr.Zero))
    throw new InvalidOperationException("Three-handle allowlist failed");
  }
  void Launch() {
   if(!SentinelReady) throw new InvalidOperationException("Fresh sentinel required");
   string root=Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
   string image=Path.Combine(root,"NativeCaptureFixtureChild.exe");
   if(image.IndexOf('"')>=0) throw new InvalidOperationException("Unsupported fixed path");
   imageLease=new FileStream(image,FileMode.Open,FileAccess.Read,FileShare.Read);
   if(Scenario==CaptureCase.EvidenceFault) evidence=new FileStream(Path.Combine(root,"child-evidence-fault.bin"),FileMode.CreateNew,FileAccess.Write,FileShare.Read,1,FileOptions.WriteThrough);
   if(environmentFault==EnvironmentObservationFault.Evidence) evidence=new FileStream(Path.Combine(root,"environment-evidence-fault.bin"),FileMode.CreateNew,FileAccess.Write,FileShare.Read,1,FileOptions.WriteThrough);
   var command=new StringBuilder("\""+image+"\" "+Scenario+" "+sentinel.ToInt64().ToString(CultureInfo.InvariantCulture)+" "+sentinelToken);
   var startup=new ChildCaptureApi.ExtendedStartup();
   startup.Startup.Size=112;startup.Startup.Flags=0x100;startup.Startup.Input=input;
   startup.Startup.Output=Channels[0].Writer;startup.Startup.Error=Channels[1].Writer;startup.Attributes=attributes;
   // All managed owners, native slots, command, image lease and attributes now exist.
   Proof.BeforeCreate();nativeOutcomeUnknown=true;createState=CreateEntryState.EnteredReturnUnknown;
   ++CreateCalls;
   bool result=ChildCaptureApi.CreateProcessW(image,command,IntPtr.Zero,IntPtr.Zero,true,environment==null?0x80000U:0x00080400U,environment==null?IntPtr.Zero:environmentAllocation.Pointer,root,ref startup,out Original);
   createState=result?CreateEntryState.ReturnedTrue:CreateEntryState.ReturnedFalse;
   CreateError=result?0:unchecked((uint)Marshal.GetLastWin32Error());
   // Exact originals already in rooted owner; no metadata/logging/callback before this.
   nativeOutcomeUnknown=false;created=result;Proof.CreateReturned(result);
   if(!result) { MarkUnknown();throw new InvalidOperationException("Fixed child rejected"); }
   if(Original.Process==IntPtr.Zero || Original.Thread==IntPtr.Zero) { nativeOutcomeUnknown=true;throw new InvalidOperationException("Missing original handles"); }
   if(Scenario==CaptureCase.PostCreateFault || environmentFault==EnvironmentObservationFault.AfterCreate) { faultInjected=true;FaultSite=1;throw injected; }
  }
  void CloseParentWriters() {
   // Each close has independent pre-call and returned-result proof. Always attempted
   // after a known Create return, including the injected post-create exception path.
   Close(ref Channels[0].Writer,Channels[0].WriterClose);
   Close(ref Channels[1].Writer,Channels[1].WriterClose);
   Close(ref input,inputClose);
  }
  void ObserveExit() {
   if(!created || Proof.ExitObserved) return;
   ++WaitCalls;
   uint wait=ChildCaptureApi.WaitForSingleObject(Original.Process,0);
   if(wait==258) return;
   if(wait!=0) { MarkUnknown();return; }
   uint code;
   ++ExitCodeReads;
   if(!ChildCaptureApi.GetExitCodeProcess(Original.Process,out code)) { MarkUnknown();return; }
   ExitCode=code;Proof.ExitObserved=true; // 259 has no special meaning after signaled wait.
  }
  void ReadStep(ChildCaptureChannel channel,int index) {
   ++channel.Visits;channel.MaxGap=Math.Max(channel.MaxGap,Rounds-channel.PreviousVisit);channel.PreviousVisit=Rounds;
   channel.Read.Poll();
   if(channel.Read.HasResult) {
    int error=channel.Read.Error;uint count=channel.Read.Count;
    if(error==0) {
     if(count>4096) { channel.Stopped=true;channel.Capture.Fault(3);MarkUnknown(); }
     else if(count>0) {
      try {
       Marshal.Copy(channel.Read.Buffer,channel.Read.Bytes,0,(int)count);
       channel.Capture.Receive(channel.Read.Bytes,(int)count);
       // Diagnostic failure has its own sink: never poison retained observation bytes.
       if(index==0 && environmentFault==EnvironmentObservationFault.Evidence && !faultInjected && channel.Capture.Total>=8) {
        faultInjected=true;FaultSite=3;
        EnvironmentFaultAtBytes=channel.Capture.RetainedCount;
        int written;
        if(!EnvironmentEvidenceSink.TryWriteCounted(evidence,out written)) { EvidenceBytesWritten=written;MarkUnknown(); }
       }
       if(index==0 && !faultInjected && channel.Capture.Total>=8 && (Scenario==CaptureCase.CaptureFault || Scenario==CaptureCase.EvidenceFault)) {
        faultInjected=true;
        if(Scenario==CaptureCase.EvidenceFault) { evidence.Write(evidenceBytes,0,1);EvidenceBytesWritten=1;FaultSite=3; }
        else FaultSite=2;
        throw injected;
       }
      } catch { channel.Capture.Fault(1);MarkUnknown(); }
     }
    } else {
     channel.Capture.ObserveTerminalError(error);
     if(!channel.Capture.Eof) { channel.Stopped=true;MarkUnknown(); }
    }
    channel.Read.Consume();
   }
   if(channel.Read.Proof.Unknown) MarkUnknown();
   if(channel.Read.Proof.SafeToRelease && !channel.Capture.Eof && !channel.Stopped) channel.Read.Submit(1,environment==null?4096:16);
  }
  void Refresh() { Proof.StdoutEof=Channels[0].Capture.Eof;Proof.StderrEof=Channels[1].Capture.Eof;Proof.IoTerminal=IoTerminal; }
  void Pump() {
   clock.Restart();long exitedAt=-1;
   while(clock.ElapsedMilliseconds<2000 && Rounds<32768) {
    ++Rounds;int first=Rounds&1;
    ReadStep(Channels[first],first);ReadStep(Channels[1-first],1-first);ObserveExit();Refresh();
    if(held!=IntPtr.Zero && Proof.ExitObserved) {
     if(exitedAt<0) exitedAt=clock.ElapsedMilliseconds;
     if(clock.ElapsedMilliseconds-exitedAt>=20) {
      HeldWriterBlockedEof=!Channels[0].Capture.Eof && !Channels[0].Read.Proof.SafeToRelease;
      Channels[0].Capture.ExpireEofBudget();MarkUnknown();Close(ref held,heldClose);
     }
    }
    if(Proof.ExitObserved && Proof.StdoutEof && Proof.StderrEof && Proof.IoTerminal) return;
    System.Threading.Thread.Sleep(1);
   }
   MarkUnknown();
  }
  void Recover() {
   // Only known submissions may be cancelled. An unavailable return is retained.
   try {
    for(int i=0;i<slots.Length;i++) if(!slots[i].Proof.SafeToRelease && !slots[i].Proof.SubmissionUnavailable) slots[i].Cancel();
    clock.Restart();
    while(clock.ElapsedMilliseconds<300) {
     for(int i=0;i<slots.Length;i++) slots[i].Poll();
     ObserveExit();Refresh();
     if(IoTerminal) break;
     System.Threading.Thread.Sleep(1);
    }
   } catch { MarkUnknown(); }
  }
  void Release() {
   Refresh();
   if(releaseAttempted || nativeOutcomeUnknown || CloseUnresolved || environmentAllocation.AllocationUnknown || environmentAllocation.ReleaseUncertain || !Proof.CanRelease) return;
   releaseAttempted=true;
   try {
    if(environment!=null && !environmentAllocation.TryRelease(createState)) { MarkUnknown();return; }
    CloseParentWriters();Close(ref held,heldClose);
    for(int i=0;i<2;i++) Close(ref Channels[i].Server,Channels[i].ServerClose);
    Close(ref Original.Thread,threadClose);Close(ref Original.Process,processClose);CloseSentinel();
    for(int i=0;i<slots.Length;i++) if(!slots[i].Release()) { MarkUnknown();return; }
    if(attributeInitialized) { ChildCaptureApi.DeleteProcThreadAttributeList(attributes);attributeInitialized=false; }
    if(attributes!=IntPtr.Zero) { Marshal.FreeHGlobal(attributes);attributes=IntPtr.Zero; }
    if(handleList!=IntPtr.Zero) { Marshal.FreeHGlobal(handleList);handleList=IntPtr.Zero; }
    if(descriptor!=IntPtr.Zero) { if(PipeNative.LocalFree(descriptor)!=IntPtr.Zero) { MarkUnknown();return; } descriptor=IntPtr.Zero; }
    if(imageLease!=null) { imageLease.Dispose();imageLease=null; }
    if(evidence!=null) { evidence.Dispose();evidence=null; }
    bool all=EnvironmentReleased && Original.Process==IntPtr.Zero && Original.Thread==IntPtr.Zero && sentinel==IntPtr.Zero && input==IntPtr.Zero && held==IntPtr.Zero &&
     attributes==IntPtr.Zero && handleList==IntPtr.Zero && descriptor==IntPtr.Zero && imageLease==null && evidence==null && !CloseUnresolved;
    for(int i=0;i<2;i++) all=all && Channels[i].Server==IntPtr.Zero && Channels[i].Writer==IntPtr.Zero;
    for(int i=0;i<slots.Length;i++) all=all && slots[i].Released;
    Proof.HandlesClosed=all;Released=all;
   } catch { MarkUnknown(); }
  }
  internal bool CapturedSentinelExcluded() {
   return Scenario==CaptureCase.Empty?Proof.ExitObserved && ExitCode==0:
    SentinelProtocol.IsExcluded(Channels[0].Capture.Retained,Channels[0].Capture.RetainedCount);
  }
  void InspectSentinel() {
   SentinelProbe=CapturedSentinelExcluded();
   SentinelUnsignaled=sentinel!=IntPtr.Zero && ChildCaptureApi.WaitForSingleObject(sentinel,0)==258;
   if(!SentinelProbe || !SentinelUnsignaled) MarkUnknown();
  }
  internal void Run() {
   Proof.UseOnce(); // Throws before setup/close/cancel/report on repeat.
   if(used) throw new InvalidOperationException("Already used");used=true;
   try {
    Prepare();
    try { Launch(); } catch { MarkUnknown(); }
    if(!nativeOutcomeUnknown) CloseParentWriters();
    if(created && !nativeOutcomeUnknown) { Pump();InspectSentinel(); }
   } catch { MarkUnknown(); }
   finally {
    Refresh();
    if(!Proof.IoTerminal) { MarkUnknown();Recover(); }
    Release();
   }
  }
  string ChannelReport(ChildCaptureChannel channel) {
   return "{\"retained\":"+N(channel.Capture.RetainedCount)+",\"discarded\":"+N(channel.Capture.Discarded)+
    ",\"read_issued\":"+N(channel.Read.Proof.Issued)+",\"read_terminal\":"+N(channel.Read.Proof.Terminal)+
    ",\"read_pending\":"+N(channel.Read.PendingReturns)+",\"read_immediate\":"+N(channel.Read.ImmediateReturns)+
    ",\"read_visits\":"+N(channel.Visits)+",\"max_read_gap\":"+N(channel.MaxGap)+"}";
  }
  internal string Report(bool passed) {
   return "{\"kind\":\"native_child_case\",\"case\":\""+Scenario+"\",\"status\":\""+(passed?"PASS":"FAIL")+
    "\",\"overall\":\""+(Unknown?"UNKNOWN":"OBSERVED")+"\",\"created\":"+B(created)+",\"exit_observed\":"+B(Proof.ExitObserved)+
    ",\"exit_code\":"+N(ExitCode)+",\"eof_stdout\":"+B(Proof.StdoutEof)+",\"eof_stderr\":"+B(Proof.StderrEof)+
    ",\"resources_released\":"+B(Released)+",\"retained_owner\":"+B(!Released)+
    ",\"stdout_bytes\":"+N(Channels[0].Capture.Total)+",\"stderr_bytes\":"+N(Channels[1].Capture.Total)+
    ",\"stdout_hash\":\""+Channels[0].Capture.Hash.ToString("x16",CultureInfo.InvariantCulture)+"\",\"stderr_hash\":\""+
    Channels[1].Capture.Hash.ToString("x16",CultureInfo.InvariantCulture)+"\",\"sentinel_probe\":"+B(SentinelProbe)+
    ",\"sentinel_unsignaled\":"+B(SentinelUnsignaled)+",\"held_writer_blocked_eof\":"+B(HeldWriterBlockedEof)+
    ",\"one_shot_refused\":"+B(OneShotRefused)+",\"rounds\":"+N(Rounds)+",\"fault_site\":"+N(FaultSite)+",\"evidence_bytes_written\":"+N(EvidenceBytesWritten)+
    ",\"create_calls\":"+N(CreateCalls)+",\"create_error\":"+N(CreateError)+",\"assertion_failed_at\":"+N(AssertionFailedAt)+",\"wait_calls\":"+N(WaitCalls)+",\"exit_code_reads\":"+N(ExitCodeReads)+
    ",\"channels\":["+ChannelReport(Channels[0])+","+ChannelReport(Channels[1])+"],\"mutation_authorized\":false}";
  }
  internal static string B(bool value) { return value?"true":"false"; }
  internal static string N(long value) { return value.ToString(CultureInfo.InvariantCulture); }
 }
}
