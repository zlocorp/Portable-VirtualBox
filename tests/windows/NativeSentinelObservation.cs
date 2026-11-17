// TEST ONLY. Pure proposed PVC2 contracts; no native operations or launch behavior.
using System;
using System.Threading;
namespace PortableVBox {
 internal sealed class SentinelArguments {
  readonly string caseName,token; readonly long candidate;
  SentinelArguments(string name,long value,string identifier) { caseName=name;candidate=value;token=identifier; }
  internal string CaseName { get { return caseName; } }
  internal long Candidate { get { return candidate; } }
  internal string Token { get { return token; } }
  internal static bool TryParse(string[] args,out SentinelArguments parsed,out int rejectionExit) {
   parsed=null; rejectionExit=90;
   if(args==null || args.Length!=3 || args[0]==null || args[1]==null || args[2]==null) return false;
   rejectionExit=91;
   switch(args[0]) {
    case "Empty": case "Binary": case "Large": case "Nonzero": case "Exit259":
    case "PostCreateFault": case "CaptureFault": case "EvidenceFault": case "WithheldEof":
    case "EnvironmentObservation": break;
    default: return false;
   }
   rejectionExit=92;
   string decimalHandle=args[1];
   if(decimalHandle.Length<1 || decimalHandle.Length>19 || decimalHandle[0]<'1' || decimalHandle[0]>'9') return false;
   long value=0;
   foreach(char digit in decimalHandle) {
    if(digit<'0' || digit>'9') return false;
    int next=digit-'0';
    if(value>(Int64.MaxValue-next)/10) return false;
    value=value*10+next;
   }
   if(!SentinelProtocol.ValidToken(args[2])) return false;
   parsed=new SentinelArguments(args[0],value,args[2]); rejectionExit=0; return true;
  }
 }
 internal enum SentinelResult { Unknown=0,Excluded=1,SameObject=2 }
 internal enum SentinelCallOutcome { NotEntered,ReturnUnavailable,KnownSuccess,KnownFailure }
 internal enum SentinelProbeStage { None,ReferenceSelfComparison,CandidateQuery,IdentityComparison }
 internal enum SentinelReason { Unknown,ReferenceAllocatedAtCandidate,CandidateInvalidAtQuery,DifferentObject,SameObject }
 internal static class SentinelProtocol {
  internal static bool ValidToken(string token) {
   if(token==null || token.Length!=32) return false;
   foreach(char digit in token) if(!((digit>='0' && digit<='9') || (digit>='a' && digit<='f'))) return false;
   return true;
  }
  internal static string ReferenceName(string token) {
   if(!ValidToken(token)) throw new ArgumentException("Fixed sentinel token required","token");
   return "Local\\pvbox-fixed-sentinel-"+token;
  }
  internal static byte[] Encode(SentinelResult result) {
   if(result!=SentinelResult.Unknown && result!=SentinelResult.Excluded && result!=SentinelResult.SameObject)
    throw new ArgumentOutOfRangeException("result");
   return new byte[]{80,86,67,50,(byte)result,0,0,165};
  }
  internal static bool IsExcluded(byte[] bytes,int count) {
   return bytes!=null && count>=8 && count<=bytes.Length &&
    bytes[0]==80 && bytes[1]==86 && bytes[2]==67 && bytes[3]==50 &&
    bytes[4]==1 && bytes[5]==0 && bytes[6]==0 && bytes[7]==165;
  }
 }
 internal interface ISentinelQueryApi {
  IntPtr OpenReference(string name,out uint error);
  bool QueryHandle(IntPtr handle,out uint flags,out uint error);
  bool CompareHandles(IntPtr first,IntPtr second,out uint error);
  bool CloseReference(IntPtr reference,out uint error);
 }
 internal sealed class SentinelObservation {
  internal readonly SentinelResult Result;
  internal readonly SentinelReason Reason;
  internal readonly SentinelCallOutcome OpenOutcome,ProbeOutcome,CloseOutcome;
  internal readonly SentinelProbeStage ProbeStage;
  internal readonly uint? OpenError,ProbeError,CloseError;
  internal SentinelObservation(SentinelResult result,SentinelReason reason,SentinelCallOutcome open,uint? openError,SentinelProbeStage stage,SentinelCallOutcome probe,uint? probeError,SentinelCallOutcome close,uint? closeError) {
   Result=result;Reason=reason;OpenOutcome=open;OpenError=openError;ProbeStage=stage;ProbeOutcome=probe;ProbeError=probeError;CloseOutcome=close;CloseError=closeError;
  }
 }
 // The child must root this owner before ObserveOnce, including unresolved returns.
 // There is deliberately no Dispose/finalizer/public cleanup path that could retry.
 internal sealed class SentinelObserver {
  readonly SentinelArguments arguments;
  int entered;
  IntPtr reference;
  SentinelReason reason;
  SentinelCallOutcome openOutcome,probeOutcome,closeOutcome;
  SentinelProbeStage probeStage;
  uint? openError,probeError,closeError;
  internal SentinelObserver(SentinelArguments arguments) {
   if(arguments==null) throw new ArgumentNullException("arguments");
   this.arguments=arguments;
  }
  internal bool HasUnresolvedReference {
   get { return openOutcome==SentinelCallOutcome.ReturnUnavailable || reference!=IntPtr.Zero; }
  }
  internal SentinelObservation Observation {
   get {
    SentinelResult result=SentinelResult.Unknown;
    if(closeOutcome==SentinelCallOutcome.KnownSuccess) {
     if(reason==SentinelReason.SameObject) result=SentinelResult.SameObject;
     else if(reason==SentinelReason.ReferenceAllocatedAtCandidate || reason==SentinelReason.CandidateInvalidAtQuery || reason==SentinelReason.DifferentObject)
      result=SentinelResult.Excluded;
    }
    return new SentinelObservation(result,reason,openOutcome,openError,probeStage,probeOutcome,probeError,closeOutcome,closeError);
   }
  }
  internal SentinelObservation ObserveOnce(ISentinelQueryApi api) {
   if(Interlocked.Exchange(ref entered,1)!=0) throw new InvalidOperationException("Sentinel observation is one-shot");
   if(api==null) throw new ArgumentNullException("api");
   // Entry is recorded before acquisition. An exception leaves ownership unknown,
   // not a fabricated failed open, and cannot trigger a speculative close.
   openOutcome=SentinelCallOutcome.ReturnUnavailable;
   try {
    uint error;
    reference=api.OpenReference(SentinelProtocol.ReferenceName(arguments.Token),out error);
    openOutcome=reference==IntPtr.Zero?SentinelCallOutcome.KnownFailure:SentinelCallOutcome.KnownSuccess;
    if(reference==IntPtr.Zero) openError=error;
   } catch(Exception) { return Observation; }
   if(openOutcome!=SentinelCallOutcome.KnownSuccess) return Observation;
   try {
    Probe(api);
   } finally {
    CloseOwnedReferenceOnce(api);
   }
   return Observation;
  }
  void Probe(ISentinelQueryApi api) {
   try {
    uint error;
    probeStage=SentinelProbeStage.ReferenceSelfComparison;
    probeOutcome=SentinelCallOutcome.ReturnUnavailable;
    bool same=api.CompareHandles(reference,reference,out error);
    probeOutcome=same?SentinelCallOutcome.KnownSuccess:SentinelCallOutcome.KnownFailure;
    if(!same) { probeError=error; return; }
    IntPtr candidate=new IntPtr(arguments.Candidate);
    if(reference==candidate) { reason=SentinelReason.ReferenceAllocatedAtCandidate; return; }

    probeStage=SentinelProbeStage.CandidateQuery;
    probeOutcome=SentinelCallOutcome.ReturnUnavailable;
    uint flags;
    bool valid=api.QueryHandle(candidate,out flags,out error);
    probeOutcome=valid?SentinelCallOutcome.KnownSuccess:SentinelCallOutcome.KnownFailure;
    if(!valid) {
     probeError=error;
     if(error==6) reason=SentinelReason.CandidateInvalidAtQuery;
     return;
    }

    probeStage=SentinelProbeStage.IdentityComparison;
    probeOutcome=SentinelCallOutcome.ReturnUnavailable;
    same=api.CompareHandles(candidate,reference,out error);
    probeOutcome=same?SentinelCallOutcome.KnownSuccess:SentinelCallOutcome.KnownFailure;
    if(same) reason=SentinelReason.SameObject;
    else {
     probeError=error;
     if(error==1656) reason=SentinelReason.DifferentObject;
    }
   } catch(Exception) {
    // The current stage was entered but no known return/error was obtained.
    // Only earlier completed branch facts may survive; no retry is permitted.
   }
  }
  void CloseOwnedReferenceOnce(ISentinelQueryApi api) {
   if(closeOutcome!=SentinelCallOutcome.NotEntered) throw new InvalidOperationException("Sentinel close is one-shot");
   closeOutcome=SentinelCallOutcome.ReturnUnavailable;
   try {
    uint error;
    bool closed=api.CloseReference(reference,out error);
    closeOutcome=closed?SentinelCallOutcome.KnownSuccess:SentinelCallOutcome.KnownFailure;
    if(closed) reference=IntPtr.Zero;
    else closeError=error;
   } catch(Exception) {
    // Keep the exact acquired reference rooted. Teardown is not close proof.
   }
  }
 }
}
