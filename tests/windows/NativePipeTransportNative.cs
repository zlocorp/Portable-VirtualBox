// TEST ONLY. Two local owned byte pipes; no process launch or production authority.
using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;

namespace PortableVBox {
 internal enum PipeCase { Empty,Short,Exact4KiB,Binary,Large,Backpressure,HotMarker,AfterFirstReadFault,EvidenceFault,
  WithheldEof,CancelBefore,CancelAfter,CancelRace,OneStreamFailure }
 internal static class PipeNative {
  internal const int Pending=997,Incomplete=996,Aborted=995,Broken=109,NoData=232,Connected=535;
  internal static readonly IntPtr Invalid=new IntPtr(-1);
  [StructLayout(LayoutKind.Sequential)] internal struct Overlapped {
   internal UIntPtr Internal,InternalHigh;
   internal uint Offset,OffsetHigh;
   internal IntPtr Event;
  }
  [StructLayout(LayoutKind.Sequential)] internal struct SecurityAttributes {
   internal int Length;
   internal IntPtr Descriptor;
   internal int Inherit;
  }
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true,ExactSpelling=true)]
  internal static extern IntPtr CreateNamedPipeW(string name,uint openMode,uint mode,uint instances,
   uint outputSize,uint inputSize,uint timeout,ref SecurityAttributes attributes);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true,ExactSpelling=true)]
  internal static extern IntPtr CreateFileW(string name,uint access,uint share,IntPtr attributes,uint disposition,uint flags,IntPtr template);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true,ExactSpelling=true)]
  internal static extern IntPtr CreateEventW(IntPtr attributes,[MarshalAs(UnmanagedType.Bool)] bool manualReset,
   [MarshalAs(UnmanagedType.Bool)] bool initialState,string name);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  internal static extern bool ResetEvent(IntPtr value);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  internal static extern bool ConnectNamedPipe(IntPtr pipe,IntPtr overlapped);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  internal static extern bool ReadFile(IntPtr file,IntPtr buffer,uint count,IntPtr countRead,IntPtr overlapped);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  internal static extern bool WriteFile(IntPtr file,IntPtr buffer,uint count,IntPtr countWritten,IntPtr overlapped);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  internal static extern bool GetOverlappedResult(IntPtr file,IntPtr overlapped,out uint count,[MarshalAs(UnmanagedType.Bool)] bool wait);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  internal static extern bool CancelIoEx(IntPtr file,IntPtr overlapped);
  [DllImport("kernel32.dll",SetLastError=true)]
  internal static extern uint WaitForMultipleObjects(uint count,IntPtr handles,[MarshalAs(UnmanagedType.Bool)] bool waitAll,uint milliseconds);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  internal static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll")] internal static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  internal static extern bool DuplicateHandle(IntPtr sourceProcess,IntPtr source,IntPtr targetProcess,out IntPtr target,
   uint access,[MarshalAs(UnmanagedType.Bool)] bool inherit,uint options);
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true,ExactSpelling=true)] [return:MarshalAs(UnmanagedType.Bool)]
  internal static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string sddl,uint revision,out IntPtr descriptor,out uint length);
  [DllImport("advapi32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  internal static extern bool GetKernelObjectSecurity(IntPtr handle,uint information,byte[] descriptor,uint length,out uint needed);
  [DllImport("kernel32.dll")] internal static extern IntPtr LocalFree(IntPtr value);
 }

 internal sealed class PipeNativeSlot {
  internal readonly PipeOperationProof Proof=new PipeOperationProof();
  internal readonly byte[] Bytes=new byte[4096];
  internal IntPtr Handle,Event,Buffer,Overlapped;
  internal bool HasResult,AllocationUnknown,ReleaseUncertain,LastQueryIncomplete;
  internal int Error,Calls,PendingReturns,ImmediateReturns,ResultQueries,CancelRequests;
  internal uint Count;
  int generation;
  bool submissionKnown;
  internal bool Released { get { return !AllocationUnknown && !ReleaseUncertain && Event==IntPtr.Zero && Buffer==IntPtr.Zero && Overlapped==IntPtr.Zero; } }
  internal void Allocate() {
   Buffer=Marshal.AllocHGlobal(4096);
   Overlapped=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(PipeNative.Overlapped)));
   AllocationUnknown=true;
   ++Calls;
   Event=PipeNative.CreateEventW(IntPtr.Zero,true,false,null);
   AllocationUnknown=false;
   if(Event==IntPtr.Zero) throw new InvalidOperationException("CreateEvent failed");
  }
  void Begin() {
   if(HasResult || !Proof.SafeToRelease || Released) throw new InvalidOperationException("Operation slot is not reusable");
   ++Calls;
   if(!PipeNative.ResetEvent(Event)) throw new InvalidOperationException("ResetEvent failed before submission");
   // Fixed verified x64 layout. StructureToPtr(struct) would box on every reissue.
   Marshal.WriteIntPtr(Overlapped,0,IntPtr.Zero);
   Marshal.WriteIntPtr(Overlapped,8,IntPtr.Zero);
   Marshal.WriteInt32(Overlapped,16,0);
   Marshal.WriteInt32(Overlapped,20,0);
   Marshal.WriteIntPtr(Overlapped,24,Event);
   Count=0; Error=0; submissionKnown=false; LastQueryIncomplete=false;
   Proof.BeforeIssue();
   generation=Proof.Issued;
  }
  void Complete(int error,uint count) {
   if(!submissionKnown) throw new InvalidOperationException("Unknown submission cannot complete");
   Proof.ExactTerminal(generation);
   Error=error; Count=count; HasResult=true;
  }
  internal void Submit(int kind,int count) {
   // kind is a private fixed choice: 0 connect, 1 read, 2 write.
   Begin();
   bool returned;
   int error;
   try {
    ++Calls;
    if(kind==0) returned=PipeNative.ConnectNamedPipe(Handle,Overlapped);
    else if(kind==1) returned=PipeNative.ReadFile(Handle,Buffer,(uint)count,IntPtr.Zero,Overlapped);
    else returned=PipeNative.WriteFile(Handle,Buffer,(uint)count,IntPtr.Zero,Overlapped);
    error=Marshal.GetLastWin32Error();
   } catch {
    // Never query/reuse a possibly zero or stale OVERLAPPED to cure a lost return.
    Proof.Unavailable();
    throw;
   }
   submissionKnown=true;
   if(returned) {
    ++ImmediateReturns;
    Poll(); // Get actual byte count for this known synchronous submission.
   } else if(error==PipeNative.Pending) {
    ++PendingReturns;
    Proof.Pending();
   } else if(kind==0 && error==PipeNative.Connected) {
    // Documented client-before-connect synchronous result, no pending connect.
    Complete(0,0);
   } else {
    // A known API FALSE other than IO_PENDING is documented submission failure,
    // not a successful transfer. This branch is NOT used for unavailable returns.
    Complete(error,0);
   }
  }
  internal bool Poll() {
   LastQueryIncomplete=false;
   if(Proof.SafeToRelease || Proof.SubmissionUnavailable || !submissionKnown) return false;
   uint transferred;
   ++Calls; ++ResultQueries;
   bool completed=PipeNative.GetOverlappedResult(Handle,Overlapped,out transferred,false);
   int error=Marshal.GetLastWin32Error();
   if(completed) { Complete(0,transferred); return true; }
   if(error==PipeNative.Incomplete) { LastQueryIncomplete=true; return false; }
   if(error==PipeNative.Aborted || error==PipeNative.Broken || error==PipeNative.NoData) {
    Complete(error,0); return true;
   }
   // Invalid handles/parameters or unfamiliar query errors are not I/O completion.
   Proof.WaitFailed();
   return false;
  }
  internal int Cancel() {
   ++Calls; ++CancelRequests;
   bool requested=PipeNative.CancelIoEx(Handle,Overlapped);
   int error=requested?0:Marshal.GetLastWin32Error();
   Proof.CancelReturned(error);
   return error;
  }
  internal void Consume() {
   if(!HasResult || !Proof.SafeToRelease) throw new InvalidOperationException("No terminal result to consume");
   HasResult=false;
  }
  internal bool Release() {
   if(!Proof.SafeToRelease || AllocationUnknown || ReleaseUncertain) return false;
   // A partially uncertain free is never retried; preserve owner and fail explicitly.
   ReleaseUncertain=true;
   if(Event!=IntPtr.Zero) {
    ++Calls;
    if(!PipeNative.CloseHandle(Event)) return false;
    Event=IntPtr.Zero;
   }
   if(Buffer!=IntPtr.Zero) { Marshal.FreeHGlobal(Buffer); Buffer=IntPtr.Zero; }
   if(Overlapped!=IntPtr.Zero) { Marshal.FreeHGlobal(Overlapped); Overlapped=IntPtr.Zero; }
   ReleaseUncertain=false;
   return true;
  }
 }

 internal sealed class PipeChannel {
  internal readonly PipeCapture Capture=new PipeCapture();
  internal readonly PipeNativeSlot Connect=new PipeNativeSlot(),Read=new PipeNativeSlot(),Write=new PipeNativeSlot();
  internal readonly PipeCloseProof ServerClose=new PipeCloseProof(),WriterClose=new PipeCloseProof(),HeldWriterClose=new PipeCloseProof();
  internal IntPtr Server,Writer,HeldWriter;
  internal int Target,Seed,Produced,ReadVisits,WriteVisits,MaxReadGap,MaxWriteGap,FirstReadRound,LastReadRound;
  internal int PreviousReadVisit,PreviousWriteVisit;
  internal bool ProducerFinished,ReadStopped;
 }

 internal sealed class PipeFixture {
  internal readonly PipeChannel[] Channels={new PipeChannel(),new PipeChannel()};
  readonly PipeNativeSlot[] slots=new PipeNativeSlot[6];
  readonly PipeCase scenario;
  readonly PipePreparationProof preparation=new PipePreparationProof();
  readonly Stopwatch clock=new Stopwatch();
  readonly byte[] diagnosticBytes=new byte[16];
  readonly byte[] aclBytes=new byte[4096];
  readonly Exception injectedFault=new IOException("Controlled diagnostic fault");
  IntPtr descriptor,waitHandles;
  FileStream diagnostic;
  bool setupOutcomeUnknown,consumed,releaseAttempted,unknown,diagnosticAttempted;
  int calls;
  internal bool SetupComplete,MainCompleted,Released,EofBudgetExpired,HeldWriterPreventedEof,DuplicateClosed,CancelWasAlreadyTerminal;
  internal int AclVerified,Rounds,FaultReached,DiagnosticBytesWritten,CancelError,CancelTerminalError,PendingWritesBeforeReads,BackpressureChecks;
  internal long BackpressureMilliseconds;
  internal int NativeCalls { get { int total=calls; for(int i=0;i<slots.Length;i++) total+=slots[i].Calls; return total; } }
  internal bool Unknown {
   get {
    if(unknown || setupOutcomeUnknown) return true;
    for(int i=0;i<2;i++) if(Channels[i].Capture.Unknown || Channels[i].ServerClose.Unresolved ||
     Channels[i].WriterClose.Unresolved || Channels[i].HeldWriterClose.Unresolved) return true;
    for(int i=0;i<slots.Length;i++) if(slots[i].Proof.Unknown) return true;
    return false;
   }
  }
  internal bool StorageReleaseEligible {
   get {
    if(setupOutcomeUnknown) return false;
    for(int i=0;i<2;i++) if(Channels[i].ServerClose.Unresolved || Channels[i].WriterClose.Unresolved ||
     Channels[i].HeldWriterClose.Unresolved) return false;
    for(int i=0;i<slots.Length;i++)
     if(!slots[i].Proof.SafeToRelease || slots[i].AllocationUnknown || slots[i].ReleaseUncertain) return false;
    return true;
   }
  }
  internal PipeFixture(PipeCase value) {
   scenario=value;
   for(int i=0;i<2;i++) {
    slots[i*3]=Channels[i].Connect; slots[i*3+1]=Channels[i].Read; slots[i*3+2]=Channels[i].Write;
    Channels[i].Seed=i==0?0:71;
   }
   int left=0,right=0;
   switch(value) {
    case PipeCase.Short: left=17;right=1;break;
    case PipeCase.Exact4KiB: left=4096;right=4096;break;
    case PipeCase.Binary: left=4097;right=257;break;
    case PipeCase.Large: case PipeCase.Backpressure: case PipeCase.AfterFirstReadFault: case PipeCase.EvidenceFault: left=196731;right=204829;break;
    case PipeCase.HotMarker: left=262267;right=17;break;
    case PipeCase.WithheldEof: left=17;right=257;break;
    case PipeCase.CancelAfter: case PipeCase.CancelRace: left=17;break;
    case PipeCase.OneStreamFailure: right=196731;break;
   }
   Channels[0].Target=left; Channels[1].Target=right;
  }
  internal void Prepare() {
   preparation.BeforePrepare(); // Irreversible before the first allocation/native call.
   if(SetupComplete || consumed) throw new InvalidOperationException("Fixture setup cannot repeat");
   if(IntPtr.Size!=8) throw new InvalidOperationException("x64 required");
   if(Marshal.SizeOf(typeof(PipeNative.Overlapped))!=32 || Marshal.SizeOf(typeof(PipeNative.SecurityAttributes))!=24)
    throw new InvalidOperationException("Native x64 structure layout mismatch");
   // Allocate every native slot and wait array before submitting even the first connect.
   for(int i=0;i<slots.Length;i++) slots[i].Allocate();
   waitHandles=Marshal.AllocHGlobal(IntPtr.Size*slots.Length);
   if(scenario==PipeCase.EvidenceFault) {
    string root=Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
    diagnostic=new FileStream(Path.Combine(root,"pipe-diagnostic-fault.bin"),FileMode.CreateNew,FileAccess.Write,FileShare.Read,1,FileOptions.WriteThrough);
   }
   string sid;
   using(WindowsIdentity identity=WindowsIdentity.GetCurrent()) sid=identity.User.Value;
   string sddl="D:P(A;;GA;;;SY)(A;;GA;;;"+sid+")";
   uint length;
   setupOutcomeUnknown=true; ++calls;
   bool converted=PipeNative.ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl,1,out descriptor,out length);
   setupOutcomeUnknown=false;
   if(!converted) throw new InvalidOperationException("Fixture DACL construction failed");
   var attributes=new PipeNative.SecurityAttributes();
   attributes.Length=Marshal.SizeOf(typeof(PipeNative.SecurityAttributes));
   attributes.Descriptor=descriptor; attributes.Inherit=0;
   for(int i=0;i<2;i++) {
    PipeChannel channel=Channels[i];
    string name=@"\\.\pipe\pvbox-owned-transport-"+Guid.NewGuid().ToString("N");
    // Inbound | OVERLAPPED | FIRST_PIPE_INSTANCE; byte mode | REJECT_REMOTE_CLIENTS.
    setupOutcomeUnknown=true; ++calls;
    channel.Server=PipeNative.CreateNamedPipeW(name,0x40080001,8,1,4096,4096,0,ref attributes);
    setupOutcomeUnknown=false;
    if(channel.Server==PipeNative.Invalid) { channel.Server=IntPtr.Zero; throw new InvalidOperationException("CreateNamedPipe failed"); }
    VerifyAcl(channel.Server,sid);
    channel.Connect.Handle=channel.Server; channel.Read.Handle=channel.Server;
    channel.Connect.Submit(0,0);
    setupOutcomeUnknown=true; ++calls;
    channel.Writer=PipeNative.CreateFileW(name,0x40000000,0,IntPtr.Zero,3,0x40000000,IntPtr.Zero);
    setupOutcomeUnknown=false;
    if(channel.Writer==PipeNative.Invalid) { channel.Writer=IntPtr.Zero; throw new InvalidOperationException("Open owned pipe writer failed"); }
    channel.Write.Handle=channel.Writer;
   }
   clock.Restart();
   while(clock.ElapsedMilliseconds<2000) {
    bool done=true;
    for(int i=0;i<2;i++) { Channels[i].Connect.Poll(); if(!Channels[i].Connect.HasResult) done=false; }
    if(done) break;
    WaitPending();
   }
   for(int i=0;i<2;i++) {
    PipeNativeSlot connect=Channels[i].Connect;
    if(!connect.HasResult || connect.Error!=0) throw new InvalidOperationException("Owned connection failed or timed out");
    connect.Consume();
   }
   if(scenario==PipeCase.WithheldEof) {
    IntPtr process=PipeNative.GetCurrentProcess();
    setupOutcomeUnknown=true; ++calls;
    bool duplicated=PipeNative.DuplicateHandle(process,Channels[0].Writer,process,out Channels[0].HeldWriter,0,false,2);
    setupOutcomeUnknown=false;
    if(!duplicated) { Channels[0].HeldWriter=IntPtr.Zero; throw new InvalidOperationException("Owned writer duplication failed"); }
   }
   SetupComplete=true;
  }
  void VerifyAcl(IntPtr handle,string sid) {
   uint needed;
   ++calls;
   if(!PipeNative.GetKernelObjectSecurity(handle,4,aclBytes,(uint)aclBytes.Length,out needed) || needed>aclBytes.Length)
    throw new InvalidOperationException("Fixture ACL inspection failed");
   var security=new RawSecurityDescriptor(aclBytes,0);
   if((security.ControlFlags&ControlFlags.DiscretionaryAclProtected)==0 || security.DiscretionaryAcl==null || security.DiscretionaryAcl.Count!=2)
    throw new InvalidOperationException("Fixture DACL is not explicit and restricted");
   bool identity=false,system=false;
   foreach(GenericAce item in security.DiscretionaryAcl) {
    CommonAce ace=item as CommonAce;
    if(ace==null || ace.AceQualifier!=AceQualifier.AccessAllowed || ace.AceFlags!=AceFlags.None)
     throw new InvalidOperationException("Unexpected fixture ACE");
    string value=ace.SecurityIdentifier.Value;
    if(value==sid) identity=true;
    if(value=="S-1-5-18") system=true;
    if(value!=sid && value!="S-1-5-18") throw new InvalidOperationException("Unexpected fixture principal");
   }
   if(!identity || !system) throw new InvalidOperationException("Fixture identity/SYSTEM grants missing");
   ++AclVerified;
  }
  void WaitPending() {
   int count=0;
   for(int i=0;i<slots.Length;i++) if(!slots[i].Proof.SafeToRelease && !slots[i].Proof.SubmissionUnavailable)
    Marshal.WriteIntPtr(waitHandles,(count++)*IntPtr.Size,slots[i].Event);
   if(count==0) return;
   ++calls;
   uint result=PipeNative.WaitForMultipleObjects((uint)count,waitHandles,false,1);
   if(result==0xffffffff || (result>=count && result!=258)) {
    unknown=true;
    for(int i=0;i<slots.Length;i++) if(!slots[i].Proof.SafeToRelease) slots[i].Proof.WaitFailed();
   }
   // Even a signaled event never completes a slot. Only Poll may do that.
  }
  void ReadStep(PipeChannel channel) {
   ++channel.ReadVisits;
   channel.MaxReadGap=Math.Max(channel.MaxReadGap,Rounds-channel.PreviousReadVisit);
   channel.PreviousReadVisit=Rounds;
   channel.Read.Poll();
   if(channel.Read.HasResult) {
    int error=channel.Read.Error;
    uint count=channel.Read.Count;
    if(error==0) {
     if(count>4096) throw new InvalidOperationException("Native read exceeded stable buffer");
     if(count>0) {
      Marshal.Copy(channel.Read.Buffer,channel.Read.Bytes,0,(int)count);
      channel.Capture.Receive(channel.Read.Bytes,(int)count);
      if(channel.FirstReadRound==0) channel.FirstReadRound=Rounds;
      channel.LastReadRound=Rounds;
      if(channel==Channels[0] && !diagnosticAttempted && (scenario==PipeCase.AfterFirstReadFault || scenario==PipeCase.EvidenceFault)) {
       diagnosticAttempted=true;
       try {
        if(scenario==PipeCase.EvidenceFault) {
         diagnostic.Write(diagnosticBytes,0,diagnosticBytes.Length);
         DiagnosticBytesWritten=diagnosticBytes.Length;
         FaultReached=2; // Actual controlled before-flush site, not an OS disk failure.
        } else FaultReached=1;
        throw injectedFault;
       } catch(IOException) { channel.Capture.Fault(FaultReached==0?5:FaultReached); unknown=true; }
      }
     }
     // A successful empty read is data of length zero, not EOF.
    } else {
     channel.Capture.ObserveTerminalError(error);
     if(!channel.Capture.Eof) { channel.ReadStopped=true; unknown=true; }
    }
    channel.Read.Consume();
   }
   if(channel.Read.Proof.SafeToRelease && !channel.ReadStopped && !channel.Capture.Eof) channel.Read.Submit(1,4096);
  }
  void WriteStep(PipeChannel channel) {
   ++channel.WriteVisits;
   channel.MaxWriteGap=Math.Max(channel.MaxWriteGap,Rounds-channel.PreviousWriteVisit);
   channel.PreviousWriteVisit=Rounds;
   channel.Write.Poll();
   if(channel.Write.HasResult) HarvestWrite(channel);
   if(channel.Produced==channel.Target && channel.Write.Proof.SafeToRelease) {
    channel.ProducerFinished=true;
    CloseKnown(ref channel.Writer,channel.WriterClose);
   } else if(channel.Write.Proof.SafeToRelease && !channel.ProducerFinished) SubmitWrite(channel);
  }
  void SubmitWrite(PipeChannel channel) {
   int count=Math.Min(4096,channel.Target-channel.Produced);
   for(int i=0;i<count;i++) channel.Write.Bytes[i]=NativePipeTransportTests.Pattern(channel.Produced+i,channel.Seed);
   Marshal.Copy(channel.Write.Bytes,0,channel.Write.Buffer,count);
   channel.Write.Submit(2,count);
  }
  void HarvestWrite(PipeChannel channel) {
   if(channel.Write.Error!=0 || channel.Write.Count==0 || channel.Write.Count>(uint)Math.Min(4096,channel.Target-channel.Produced))
    throw new InvalidOperationException("Finite producer did not complete its write");
   channel.Produced+=(int)channel.Write.Count;
   channel.Write.Consume();
  }
  bool Complete { get {
   for(int i=0;i<2;i++) if(!Channels[i].ProducerFinished || (!Channels[i].Capture.Eof && !Channels[i].ReadStopped)) return false;
   return StorageReleaseEligible;
  } }
  void Round() {
   ++Rounds;
   // Fixed work per visit; alternate first channel, never drain a hot channel to exhaustion.
   int first=Rounds&1;
   ReadStep(Channels[first]); WriteStep(Channels[first]);
   ReadStep(Channels[1-first]); WriteStep(Channels[1-first]);
  }
  bool Pump(int milliseconds,bool untilData) {
   clock.Restart();
   while(clock.ElapsedMilliseconds<milliseconds && Rounds<32768) {
    Round();
    if(Complete) return true;
    if(untilData && Channels[0].Capture.Total==Channels[0].Target && Channels[1].Capture.Total==Channels[1].Target &&
     Channels[0].ProducerFinished && Channels[1].ProducerFinished) return true;
    WaitPending();
   }
   return false;
  }
  void Await(PipeNativeSlot slot) {
   clock.Restart();
   while(!slot.HasResult && clock.ElapsedMilliseconds<2000) { slot.Poll(); if(!slot.HasResult) WaitPending(); }
   if(!slot.HasResult) throw new InvalidOperationException("Exact slot completion budget expired");
  }
  void Prefill() {
   SubmitWrite(Channels[0]); Await(Channels[0].Write); HarvestWrite(Channels[0]);
   Channels[0].Read.Submit(1,4096);
  }
  void ReachBackpressure() {
   // A historical IO_PENDING return is insufficient: exact current queries on
   // BOTH writes must still say IO_INCOMPLETE across a bounded no-reader interval.
   // Completed writes are harvested and finite filling continues, never adopted
   // as proof of backpressure. Unknown query failures fail this case explicitly.
   long stableSince=-1;
   clock.Restart();
   while(clock.ElapsedMilliseconds<2000) {
    bool bothIncomplete=true;
    for(int i=0;i<2;i++) {
     PipeChannel channel=Channels[i];
     if(Channels[0].Read.Proof.Issued!=0 || Channels[1].Read.Proof.Issued!=0)
      throw new InvalidOperationException("Backpressure warm-up unexpectedly issued reads");
     if(channel.Write.HasResult) HarvestWrite(channel);
     if(channel.Write.Proof.SafeToRelease) {
      if(channel.Write.Proof.Issued>=16) throw new InvalidOperationException("Fixed backpressure fill bound exhausted");
      SubmitWrite(channel);
     }
     channel.Write.Poll();
     if(channel.Write.HasResult) { HarvestWrite(channel); bothIncomplete=false; }
     else if(channel.Write.LastQueryIncomplete && channel.Write.PendingReturns>0) ++BackpressureChecks;
     else throw new InvalidOperationException("Backpressure query was not known IO_INCOMPLETE");
    }
    if(bothIncomplete) {
     if(stableSince<0) stableSince=clock.ElapsedMilliseconds;
     else if(clock.ElapsedMilliseconds-stableSince>=10) {
      // Both LastQueryIncomplete facts were freshly obtained in this iteration.
      BackpressureMilliseconds=clock.ElapsedMilliseconds-stableSince;
      PendingWritesBeforeReads=2;
      return;
     }
    } else stableSince=-1;
    WaitPending();
   }
   throw new InvalidOperationException("Exact backpressure observation budget expired");
  }
  void CancellationCase() {
   PipeChannel channel=Channels[0];
   if(scenario==PipeCase.CancelAfter) {
    Prefill(); Await(channel.Read);
    CancelWasAlreadyTerminal=channel.Read.Proof.SafeToRelease;
   } else {
    channel.Read.Submit(1,4096);
    if(channel.Read.PendingReturns!=1 || channel.Read.Proof.SafeToRelease) throw new InvalidOperationException("Cancellation needs genuinely pending read");
    if(scenario==PipeCase.CancelRace) SubmitWrite(channel);
   }
   CancelError=channel.Read.Cancel();
   Await(channel.Read);
   CancelTerminalError=channel.Read.Error;
   // The normal fair loop consumes this exact terminal result and finishes other I/O.
  }
  internal void Run() {
   if(consumed || !SetupComplete) throw new InvalidOperationException("Fixture unavailable or consumed");
   consumed=true;
   if(scenario==PipeCase.Short || scenario==PipeCase.Exact4KiB) Prefill();
   if(scenario==PipeCase.Backpressure) ReachBackpressure();
   if(scenario==PipeCase.Large || scenario==PipeCase.HotMarker) {
    Channels[0].Read.Submit(1,4096); Channels[1].Read.Submit(1,4096);
    if(Channels[0].Read.PendingReturns==0 || Channels[1].Read.PendingReturns==0)
     throw new InvalidOperationException("Empty connected reads did not pend");
   }
   if(scenario==PipeCase.CancelBefore || scenario==PipeCase.CancelAfter || scenario==PipeCase.CancelRace || scenario==PipeCase.OneStreamFailure)
    CancellationCase();
   if(scenario==PipeCase.WithheldEof) {
    if(!Pump(3000,true)) throw new InvalidOperationException("Held-writer data did not drain");
    bool completed=Pump(20,false);
    EofBudgetExpired=!completed;
    if(EofBudgetExpired) { Channels[0].Capture.ExpireEofBudget(); unknown=true; }
    HeldWriterPreventedEof=!Channels[0].Capture.Eof && !Channels[0].Read.Proof.SafeToRelease;
    CloseKnown(ref Channels[0].HeldWriter,Channels[0].HeldWriterClose);
    DuplicateClosed=Channels[0].HeldWriter==IntPtr.Zero;
   }
   MainCompleted=Pump(3000,false);
   if(!MainCompleted) { unknown=true; throw new InvalidOperationException("Main transport budget expired"); }
  }
  internal void DrainCancellation() {
   // Bounded trusted cancellation only. No Dispose, finalizer, background thread or kill.
   try {
    for(int i=0;i<slots.Length;i++) if(!slots[i].Proof.SafeToRelease) {
     unknown=true;
     if(!slots[i].Proof.SubmissionUnavailable) slots[i].Cancel();
    }
    clock.Restart();
    while(!StorageReleaseEligible && clock.ElapsedMilliseconds<2000) {
     for(int i=0;i<slots.Length;i++) slots[i].Poll();
     if(!StorageReleaseEligible) WaitPending();
    }
    if(!StorageReleaseEligible) unknown=true;
   } catch { unknown=true; } // Keep rooted state; failure never grants cleanup.
  }
  void CloseKnown(ref IntPtr handle,PipeCloseProof proof) {
   if(handle==IntPtr.Zero) return;
   proof.BeforeClose(); // The owner already roots this per-handle state before the call.
   ++calls;
   bool closed=PipeNative.CloseHandle(handle);
   proof.Returned(closed);
   if(!closed) throw new InvalidOperationException("Owned handle close failed");
   handle=IntPtr.Zero;
  }
  internal void MarkFailure() { unknown=true; }
  internal void ReleaseFixture() {
   if(releaseAttempted || !StorageReleaseEligible) return;
   releaseAttempted=true;
   try {
    for(int i=0;i<2;i++) {
     CloseKnown(ref Channels[i].HeldWriter,Channels[i].HeldWriterClose);
     CloseKnown(ref Channels[i].Writer,Channels[i].WriterClose);
     CloseKnown(ref Channels[i].Server,Channels[i].ServerClose);
    }
    for(int i=0;i<slots.Length;i++) if(!slots[i].Release()) { unknown=true; return; }
    if(descriptor!=IntPtr.Zero) {
     ++calls;
     if(PipeNative.LocalFree(descriptor)!=IntPtr.Zero) { unknown=true; return; }
     descriptor=IntPtr.Zero;
    }
    if(waitHandles!=IntPtr.Zero) { Marshal.FreeHGlobal(waitHandles); waitHandles=IntPtr.Zero; }
    if(diagnostic!=null) { diagnostic.Dispose(); diagnostic=null; }
    // Prove release from actual owned fields, including duplicate writers and events.
    bool closed=descriptor==IntPtr.Zero && waitHandles==IntPtr.Zero && diagnostic==null;
    for(int i=0;i<2;i++) closed=closed && Channels[i].Server==IntPtr.Zero && Channels[i].Writer==IntPtr.Zero && Channels[i].HeldWriter==IntPtr.Zero;
    for(int i=0;i<slots.Length;i++) closed=closed && slots[i].Released;
    Released=closed && StorageReleaseEligible;
   } catch { unknown=true; }
  }
  static string Bool(bool value) { return value?"true":"false"; }
  static string Number(long value) { return value.ToString(CultureInfo.InvariantCulture); }
  string ChannelReport(PipeChannel value) {
   return "{\"read_issued\":"+Number(value.Read.Proof.Issued)+",\"read_terminal\":"+Number(value.Read.Proof.Terminal)+
    ",\"write_issued\":"+Number(value.Write.Proof.Issued)+",\"write_terminal\":"+Number(value.Write.Proof.Terminal)+
    ",\"connect_issued\":"+Number(value.Connect.Proof.Issued)+",\"connect_terminal\":"+Number(value.Connect.Proof.Terminal)+
    ",\"read_pending\":"+Number(value.Read.PendingReturns)+",\"read_immediate\":"+Number(value.Read.ImmediateReturns)+
    ",\"write_pending\":"+Number(value.Write.PendingReturns)+",\"result_queries\":"+Number(value.Read.ResultQueries+value.Write.ResultQueries+value.Connect.ResultQueries)+
    ",\"produced\":"+Number(value.Produced)+",\"producer_completed\":"+Bool(value.ProducerFinished)+
    ",\"observed\":"+Number(value.Capture.Total)+",\"retained\":"+Number(value.Capture.RetainedCount)+
    ",\"discarded\":"+Number(value.Capture.Discarded)+",\"fnv1a64\":\""+value.Capture.Hash.ToString("x16",CultureInfo.InvariantCulture)+
    "\",\"eof\":"+Bool(value.Capture.Eof)+",\"read_stopped\":"+Bool(value.ReadStopped)+
    ",\"read_visits\":"+Number(value.ReadVisits)+",\"write_visits\":"+Number(value.WriteVisits)+
    ",\"max_read_gap\":"+Number(value.MaxReadGap)+",\"max_write_gap\":"+Number(value.MaxWriteGap)+
    ",\"first_read_round\":"+Number(value.FirstReadRound)+",\"last_read_round\":"+Number(value.LastReadRound)+"}";
  }
  internal string Report(bool assertionsPassed) {
   // Fixed field/case names and bounded numeric values only, no external strings or raw data.
   return "{\"kind\":\"native_pipe_case\",\"case\":\""+scenario+"\",\"status\":\""+(assertionsPassed&&Released?"PASS":"FAIL")+
    "\",\"overall\":\""+(Unknown?"UNKNOWN":"OBSERVED")+"\",\"native_calls\":"+Number(NativeCalls)+
    ",\"setup_complete\":"+Bool(SetupComplete)+",\"acl_verified\":"+Number(AclVerified)+
    ",\"storage_release_eligible\":"+Bool(StorageReleaseEligible)+",\"resources_released\":"+Bool(Released)+
    ",\"retained_owner\":"+Bool(!Released)+",\"rounds\":"+Number(Rounds)+",\"fault_site\":"+Number(FaultReached)+
    ",\"pending_writes_before_reads\":"+Number(PendingWritesBeforeReads)+
    ",\"backpressure_checks\":"+Number(BackpressureChecks)+",\"backpressure_milliseconds\":"+Number(BackpressureMilliseconds)+
    ",\"diagnostic_bytes_written\":"+Number(DiagnosticBytesWritten)+",\"cancel_error\":"+Number(CancelError)+
    ",\"cancel_terminal_error\":"+Number(CancelTerminalError)+",\"cancel_was_already_terminal\":"+Bool(CancelWasAlreadyTerminal)+
    ",\"eof_budget_expired\":"+Bool(EofBudgetExpired)+",\"held_writer_prevented_eof\":"+Bool(HeldWriterPreventedEof)+
    ",\"duplicate_closed\":"+Bool(DuplicateClosed)+",\"channels\":["+ChannelReport(Channels[0])+","+ChannelReport(Channels[1])+
    "],\"mutation_authorized\":false}";
  }
 }
}
