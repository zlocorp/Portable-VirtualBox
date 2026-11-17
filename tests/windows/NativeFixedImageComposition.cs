// TEST ONLY. Adapters and observations for the existing owner, not another lifecycle.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
namespace PortableVBox {
 internal interface IChildCaptureProcessCalls {
  FixedImageCallDomain Domain { get; }
  bool CreateProcessW(string image,StringBuilder command,IntPtr processSecurity,IntPtr threadSecurity,bool inherit,uint flags,IntPtr environment,string directory,ref ChildCaptureApi.ExtendedStartup startup,out ChildCaptureApi.ProcessInfo information);
  bool QueryFullProcessImageNameW(IntPtr process,uint flags,StringBuilder buffer,ref uint capacity);
  uint WaitForSingleObject(IntPtr handle,uint milliseconds);
  bool GetExitCodeProcess(IntPtr process,out uint code);
  bool CloseHandle(IntPtr handle);
  uint CaptureLastError();
 }
 internal interface IChildCaptureFlow {
  FixedImageCallDomain Domain { get; }
  void PrepareTransport(ChildCaptureOwner owner);
  void CloseParentWriters(ChildCaptureOwner owner);
  void Pump(ChildCaptureOwner owner);
  void InspectSentinel(ChildCaptureOwner owner);
  void Recover(ChildCaptureOwner owner);
 }
 // Extends the unchanged sentinel interface only for the closed recording bundle.
 internal interface IChildCaptureRecordingSentinelCalls : IFreshSentinelNativeCalls {
  FixedImageCallDomain Domain { get; }
 }
 internal sealed class ChildCaptureProcessCalls : IChildCaptureProcessCalls {
  internal static readonly ChildCaptureProcessCalls Instance=new ChildCaptureProcessCalls();
  ChildCaptureProcessCalls() { }
  public FixedImageCallDomain Domain { get { return FixedImageCallDomain.Native; } }
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,ExactSpelling=true,SetLastError=true,EntryPoint="QueryFullProcessImageNameW")]
  [return:MarshalAs(UnmanagedType.Bool)] static extern bool QueryFullProcessImageNameWNative(IntPtr process,uint flags,StringBuilder buffer,ref uint capacity);
  public bool CreateProcessW(string image,StringBuilder command,IntPtr processSecurity,IntPtr threadSecurity,bool inherit,uint flags,IntPtr environment,string directory,ref ChildCaptureApi.ExtendedStartup startup,out ChildCaptureApi.ProcessInfo information) { return ChildCaptureApi.CreateProcessW(image,command,processSecurity,threadSecurity,inherit,flags,environment,directory,ref startup,out information); }
  public bool QueryFullProcessImageNameW(IntPtr process,uint flags,StringBuilder buffer,ref uint capacity) { return QueryFullProcessImageNameWNative(process,flags,buffer,ref capacity); }
  public uint WaitForSingleObject(IntPtr handle,uint milliseconds) { return ChildCaptureApi.WaitForSingleObject(handle,milliseconds); }
  public bool GetExitCodeProcess(IntPtr process,out uint code) { return ChildCaptureApi.GetExitCodeProcess(process,out code); }
  public bool CloseHandle(IntPtr handle) { return PipeNative.CloseHandle(handle); }
  public uint CaptureLastError() { return unchecked((uint)Marshal.GetLastWin32Error()); }
 }
 internal sealed class ChildCaptureFlow : IChildCaptureFlow {
  internal static readonly ChildCaptureFlow Instance=new ChildCaptureFlow();
  ChildCaptureFlow() { }
  public FixedImageCallDomain Domain { get { return FixedImageCallDomain.Native; } }
  public void PrepareTransport(ChildCaptureOwner owner) { owner.Prepare(); }
  public void CloseParentWriters(ChildCaptureOwner owner) { owner.CloseParentWriters(); }
  public void Pump(ChildCaptureOwner owner) { owner.Pump(); }
  public void InspectSentinel(ChildCaptureOwner owner) { owner.InspectSentinel(); }
  public void Recover(ChildCaptureOwner owner) { owner.Recover(); }
 }
 internal sealed class FixedImageCompositionBindings {
  internal static readonly FixedImageCompositionBindings Native=new FixedImageCompositionBindings(FixedImageCallDomain.Native,ChildCaptureProcessCalls.Instance,ChildCaptureFlow.Instance,new SentinelNativeCalls());
  internal readonly FixedImageCallDomain Domain;
  internal readonly IChildCaptureProcessCalls Process;
  internal readonly IChildCaptureFlow Flow;
  internal readonly IFreshSentinelNativeCalls Sentinel;
  FixedImageCompositionBindings(FixedImageCallDomain domain,IChildCaptureProcessCalls process,IChildCaptureFlow flow,IFreshSentinelNativeCalls sentinel) { Domain=domain;Process=process;Flow=flow;Sentinel=sentinel; }
  internal static FixedImageCompositionBindings CreateRecording(FixedFixtureImage image,IChildCaptureProcessCalls process,IChildCaptureFlow flow,IFreshSentinelNativeCalls sentinel) {
   var recordingSentinel=sentinel as IChildCaptureRecordingSentinelCalls;
   if(image==null || process==null || flow==null || recordingSentinel==null || sentinel is SentinelNativeCalls || Object.ReferenceEquals(image.Domain,FixedImageCallDomain.Native) ||
    !Object.ReferenceEquals(image.Domain,process.Domain) || !Object.ReferenceEquals(image.Domain,flow.Domain) || !Object.ReferenceEquals(image.Domain,recordingSentinel.Domain))throw new ArgumentException("One inseparable recording image/process/flow/sentinel domain required");
   return new FixedImageCompositionBindings(image.Domain,process,flow,sentinel);
  }
 }
 internal sealed class ChildCaptureOriginalHandlesObservation {
  internal readonly string State;
  internal ChildCaptureOriginalHandlesObservation(bool? invalid) { State=!invalid.HasValue?"not-observed":invalid.Value?"invalid":"valid"; }
 }
 internal sealed class FixedImageCompositionSnapshot {
  internal readonly string Json;
  internal FixedImageCompositionSnapshot(string json) { Json=json; }
 }
 internal sealed class FixedProcessImageObservation {
  internal readonly bool Entered;
  internal readonly bool? Returned,Agree;
  internal readonly uint? Error,ReturnedLength;
  internal readonly string Path,Outcome,PathState;
  internal FixedProcessImageObservation(bool entered,bool? returned,uint? error,uint? length,string path,bool? agree,string outcome,string pathState=null) { Entered=entered;Returned=returned;Error=error;ReturnedLength=length;Path=path;Agree=agree;Outcome=outcome;PathState=pathState??(!entered?"not-observed":returned!=true?"unavailable":"malformed"); }
  internal static string Classify(string raw,uint count) {
   if(count==0 || raw==null)return "malformed";
   for(int i=0;i<raw.Length;i++) {
    char c=raw[i];if(c==0)return "malformed";
    if(Char.IsHighSurrogate(c)) { if(++i>=raw.Length || !Char.IsLowSurrogate(raw[i]))return "malformed"; }
    else if(Char.IsLowSurrogate(c))return "malformed";
   }
   if(count>=32768 || count!=raw.Length)return "truncated";
   try { FixedImagePath.Validate(raw);return "valid"; } catch(ArgumentException) { return "unsupported"; }
  }
 }
 internal sealed class ChildCaptureExitObservation {
  internal readonly bool WaitEntered,CodeEntered;
  internal readonly uint? WaitReturn,WaitError,CodeError,Code;
  internal readonly bool? CodeReturn;
  internal ChildCaptureExitObservation(bool waitEntered,uint? waitReturn,uint? waitError,bool codeEntered,bool? codeReturn,uint? codeError,uint? code) { WaitEntered=waitEntered;WaitReturn=waitReturn;WaitError=waitError;CodeEntered=codeEntered;CodeReturn=codeReturn;CodeError=codeError;Code=code; }
 }
 internal sealed class ChildCaptureReleaseObservation {
  internal readonly bool Attempted,Released,ProcessCloseEntered,ThreadCloseEntered;
  internal readonly bool? ProcessCloseReturn,ThreadCloseReturn;
  internal readonly uint? ProcessCloseError,ThreadCloseError;
  internal readonly FixedImageObservation Image;
  internal ChildCaptureReleaseObservation(bool attempted,bool released,bool processEntered,bool? processReturn,uint? processError,bool threadEntered,bool? threadReturn,uint? threadError,FixedImageObservation image) {
   Attempted=attempted;Released=released;ProcessCloseEntered=processEntered;ProcessCloseReturn=processReturn;ProcessCloseError=processError;
   ThreadCloseEntered=threadEntered;ThreadCloseReturn=threadReturn;ThreadCloseError=threadError;Image=image;
  }
 }
 internal sealed partial class ChildCaptureOwner {
  readonly FixedFixtureImage.CompositionLease fixedImage;
  readonly IChildCaptureProcessCalls processCalls=ChildCaptureProcessCalls.Instance;
  readonly IChildCaptureFlow flow=ChildCaptureFlow.Instance;
  readonly List<string> compositionTrace=new List<string>();
  bool imagePreparationEntered;
  bool? originalHandlesInvalid;
  internal ChildCaptureOriginalHandlesObservation OriginalHandlesObservation { get { return new ChildCaptureOriginalHandlesObservation(originalHandlesInvalid); } }
  bool? processCloseReturn,threadCloseReturn;
  uint? processCloseError,threadCloseError;
  FixedProcessImageObservation processImageObservation=new FixedProcessImageObservation(false,null,null,null,null,null,"not-entered");
  ChildCaptureExitObservation exitObservation=new ChildCaptureExitObservation(false,null,null,false,null,null,null);
  internal FixedProcessImageObservation ProcessImageObservation { get { return processImageObservation; } }
  internal ChildCaptureExitObservation ExitObservation { get { return exitObservation; } }
  internal ChildCaptureReleaseObservation ReleaseObservation { get { return new ChildCaptureReleaseObservation(releaseAttempted,Released,processClose.Attempted,processCloseReturn,processCloseError,threadClose.Attempted,threadCloseReturn,threadCloseError,fixedImage==null?null:fixedImage.Observation); } }
  internal string[] CompositionTrace { get { return compositionTrace.ToArray(); } }
  void TraceComposition(string step) { if(fixedImage!=null)compositionTrace.Add(step); }
  internal ChildCaptureOwner(FixedFixtureImage image):this(image,FixedImageCompositionBindings.Native) { }
  internal ChildCaptureOwner(FixedFixtureImage image,FixedImageCompositionBindings bindings) {
   if(image==null)throw new ArgumentNullException("image");
   if(bindings==null || !Object.ReferenceEquals(image.Domain,bindings.Domain))throw new ArgumentException("Matching fixed image composition domain required","bindings");
   Scenario=CaptureCase.Binary;processCalls=bindings.Process;flow=bindings.Flow;sentinelCalls=bindings.Sentinel;
   for(int i=0;i<2;i++) { slots[i*2]=Channels[i].Connect;slots[i*2+1]=Channels[i].Read; }
   // Claim last. A rejected constructor cannot affect another owner's native state.
   fixedImage=image.ClaimForComposition();
  }
  bool PrepareImageOnce() {
   if(fixedImage==null)return true;
   TraceComposition("PrepareImage");
   if(imagePreparationEntered)throw new InvalidOperationException("Image preparation one-shot");imagePreparationEntered=true;
   fixedImage.PrepareOnce();
   if(!fixedImage.Ready || !fixedImage.ObserveSharing() || !fixedImage.Ready) { MarkUnknown();return false; }
   return true;
  }
  void ObserveProcessImageOnce() {
   if(fixedImage==null)return;
   if(processImageObservation.Entered || !created || nativeOutcomeUnknown || !ValidOriginal(Original.Process) || !ValidOriginal(Original.Thread))throw new InvalidOperationException("Known exact originals required for one query");
   TraceComposition("ObserveProcessImage");
   var buffer=new StringBuilder(32768);uint capacity=32768;
   processImageObservation=new FixedProcessImageObservation(true,null,null,null,null,null,"return-unavailable");
   try {
    bool returned=processCalls.QueryFullProcessImageNameW(Original.Process,0,buffer,ref capacity);
    uint? error=returned?(uint?)null:processCalls.CaptureLastError();
    processImageObservation=new FixedProcessImageObservation(true,returned,error,returned?(uint?)capacity:null,null,null,returned?"invalid-path":"returned-failure");
    if(!returned) { MarkUnknown();return; }
    string raw=buffer.ToString();string pathState=FixedProcessImageObservation.Classify(raw,capacity);
    string path=pathState=="valid" || pathState=="unsupported"?raw:null;
    processImageObservation=new FixedProcessImageObservation(true,true,null,capacity,path,null,"invalid-path",pathState);
    if(pathState!="valid") { MarkUnknown();return; }
    bool agree=FixedImagePath.Agree(fixedImage.Observation.HeldPath,path);
    processImageObservation=new FixedProcessImageObservation(true,true,null,capacity,path,agree,agree?"agreed":"different-path","valid");
    if(!agree)MarkUnknown();
   } catch { MarkUnknown(); }
   // Query diagnostics never change acquisition certainty or abort Run drainage.
  }
  string ComposedChannel(ChildCaptureChannel c) {
   return "{\"retained\":"+N(c.Capture.RetainedCount)+",\"discarded\":"+N(c.Capture.Discarded)+
    ",\"read_issued\":"+N(c.Read.Proof.Issued)+",\"read_terminal\":"+N(c.Read.Proof.Terminal)+
    ",\"read_pending\":"+N(c.Read.PendingReturns)+",\"read_immediate\":"+N(c.Read.ImmediateReturns)+
    ",\"read_visits\":"+N(c.Visits)+",\"max_read_gap\":"+N(c.MaxGap)+
    ",\"read_released\":"+B(c.Read.Released)+",\"connect_released\":"+B(c.Connect.Released)+"}";
  }
  string ComposedCapture() {
   return "{\"stdout_bytes\":"+N(Channels[0].Capture.Total)+",\"stderr_bytes\":"+N(Channels[1].Capture.Total)+
    ",\"stdout_hash\":"+FixedImageCodec.Q(Channels[0].Capture.Hash.ToString("x16",System.Globalization.CultureInfo.InvariantCulture))+
    ",\"stderr_hash\":"+FixedImageCodec.Q(Channels[1].Capture.Hash.ToString("x16",System.Globalization.CultureInfo.InvariantCulture))+
    ",\"eof_stdout\":"+B(Proof.StdoutEof)+",\"eof_stderr\":"+B(Proof.StderrEof)+",\"io_terminal\":"+B(Proof.IoTerminal)+
    ",\"sentinel_probe\":"+B(SentinelProbe)+",\"sentinel_unsignaled\":"+B(SentinelUnsignaled)+",\"one_shot_refused\":"+B(OneShotRefused)+
    ",\"rounds\":"+N(Rounds)+",\"fault_site\":"+N(FaultSite)+",\"evidence_bytes_written\":"+N(EvidenceBytesWritten)+
    ",\"held_writer_blocked_eof\":"+B(HeldWriterBlockedEof)+",\"wait_calls\":"+N(WaitCalls)+",\"exit_code_reads\":"+N(ExitCodeReads)+
    ",\"channels\":["+ComposedChannel(Channels[0])+","+ComposedChannel(Channels[1])+"]}";
  }
  static string ReturnState(bool entered,bool? returned) { return !entered?"not-entered":!returned.HasValue?"return-unknown":returned.Value?"returned-success":"returned-failure"; }
  static string ComposedProcess(FixedProcessImageObservation q,ChildCaptureExitObservation e) {
   return "{\"query_state\":"+FixedImageCodec.Q(ReturnState(q.Entered,q.Returned))+",\"query_error\":"+FixedImageCodec.N(q.Error)+
    ",\"query_return_chars\":"+FixedImageCodec.N(q.ReturnedLength)+",\"image_path\":"+FixedImageCodec.Q(q.Path)+",\"path_state\":"+FixedImageCodec.Q(q.PathState)+
    ",\"comparison\":"+FixedImageCodec.Q(!q.Agree.HasValue?"not-performed":q.Agree.Value?"match":"mismatch")+
    ",\"exit_wait_state\":"+FixedImageCodec.Q(!e.WaitEntered?"not-entered":e.WaitReturn.HasValue?"returned":"return-unknown")+
    ",\"exit_wait_result\":"+FixedImageCodec.N(e.WaitReturn)+",\"exit_wait_error\":"+FixedImageCodec.N(e.WaitError)+
    ",\"exit_code_state\":"+FixedImageCodec.Q(ReturnState(e.CodeEntered,e.CodeReturn))+",\"exit_code_error\":"+FixedImageCodec.N(e.CodeError)+",\"exit_code\":"+FixedImageCodec.N(e.Code)+"}";
  }
  internal FixedImageCompositionSnapshot CompositionSnapshot(string scenario,bool passed) {
   if(fixedImage==null || !used || !OneShotRefused)throw new InvalidOperationException("Composed Run and one-shot assertion required before snapshot");
   var o=fixedImage.Observation;var write=fixedImage.WriteProbeObservation;var delete=fixedImage.DeleteProbeObservation;
   var q=processImageObservation;var e=exitObservation;var originals=OriginalHandlesObservation;
   bool valid=createState==CreateEntryState.ReturnedTrue && originals.State=="valid";
   string refusal=o.Refusal;
   if(refusal=="none" && ((write!=null && (write.OpenState!="returned-failure" || write.OpenError!=32)) || (delete!=null && (delete.OpenState!="returned-failure" || delete.OpenError!=32))))refusal="sharing-failure";
   string composition="{\"claim_state\":\"claimed\",\"create_state\":"+FixedImageCodec.Q(createState.ToString())+
    ",\"create_error\":"+FixedImageCodec.N(createState==CreateEntryState.ReturnedFalse?(long?)CreateError:null)+
    ",\"original_handles_state\":"+FixedImageCodec.Q(originals.State)+",\"overall\":"+FixedImageCodec.Q(Unknown?"UNKNOWN":"OBSERVED")+
    ",\"image_release_state\":"+FixedImageCodec.Q(fixedImage.Released?"released":"retained")+",\"owner_release_state\":"+FixedImageCodec.Q(Released?"released":"retained")+
    ",\"capture\":"+(valid?ComposedCapture():"null")+"}";
   return new FixedImageCompositionSnapshot("{\"kind\":\"fixed_image_case\",\"schema\":2,\"stage\":\"composed\","+
    FixedImageEvidence.Fields(fixedImage.Expected,o,scenario,passed,FixedImageEvidence.Probe(write),FixedImageEvidence.Probe(delete),refusal,CreateCalls)+
    ",\"process_observation\":"+(valid?ComposedProcess(q,e):"null")+",\"composition\":"+composition+"}");
  }
  static bool ValidOriginal(IntPtr handle) { return handle!=IntPtr.Zero && handle!=new IntPtr(-1); }
  void CloseOriginal(ref IntPtr handle,PipeCloseProof close,bool process) {
   if(handle==IntPtr.Zero)return;
   close.BeforeClose();
   bool result=processCalls.CloseHandle(handle);
   uint? error=result?(uint?)null:processCalls.CaptureLastError();
   if(process) { processCloseReturn=result;processCloseError=error; } else { threadCloseReturn=result;threadCloseError=error; }
   close.Returned(result);
   if(!result)throw new InvalidOperationException("Exact original handle close failed");handle=IntPtr.Zero;
  }
 }
}
