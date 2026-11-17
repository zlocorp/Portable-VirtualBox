// TEST ONLY. Managed behavioral contracts, no native calls.
using System;
using System.Collections.Generic;
namespace PortableVBox {
 public static class NativeChildCaptureTests {
  static void Check(bool value,string message) { if(!value) throw new Exception(message); }
  static void Refuses(Action action) { bool refused=false; try { action(); } catch(InvalidOperationException) { refused=true; } Check(refused,"one-shot refusal"); }

  const string SentinelToken="0123456789abcdef0123456789abcdef";
  static SentinelArguments Arguments(string candidate) {
   SentinelArguments parsed; int rejection;
   Check(SentinelArguments.TryParse(new[]{"Binary",candidate,SentinelToken},out parsed,out rejection),"actual parser accepts observer input");
   Check(rejection==0 && parsed!=null,"successful parser result"); return parsed;
  }
  static void RejectArguments(string[] args,int expected) {
   SentinelArguments parsed; int rejection;
   Check(!SentinelArguments.TryParse(args,out parsed,out rejection),"actual parser rejects invalid argument shape/value");
   Check(parsed==null && rejection==expected,"parser rejection preserves null and exact exit "+expected);
  }
  public static int RunSentinelArguments() {
   string[] cases={"Empty","Binary","Large","Nonzero","Exit259","PostCreateFault","CaptureFault","EvidenceFault","WithheldEof","EnvironmentObservation"};
   foreach(string name in cases) foreach(string candidate in new[]{"1","9223372036854775807"}) {
    SentinelArguments parsed; int rejection;
    Check(SentinelArguments.TryParse(new[]{name,candidate,SentinelToken},out parsed,out rejection),"actual parser accepts exact case and positive Int64");
    Check(rejection==0 && parsed.CaseName==name && parsed.Candidate==(candidate=="1"?1:Int64.MaxValue) && parsed.Token==SentinelToken,"immutable parsed values");
   }
   RejectArguments(null,90); RejectArguments(new string[0],90);
   RejectArguments(new[]{"Binary"},90); RejectArguments(new[]{"Binary","1"},90); RejectArguments(new[]{"Binary","1",SentinelToken,"extra"},90);
   for(int i=0;i<3;i++) { string[] args={"Binary","1",SentinelToken}; args[i]=null; RejectArguments(args,90); }
   foreach(string name in cases) RejectArguments(new[]{name.ToLowerInvariant(),"1",SentinelToken},91);
   foreach(string name in new[]{"binary","BINARY"," Binary","Binary ","Unknown",""}) RejectArguments(new[]{name,"1",SentinelToken},91);
   foreach(string candidate in new[]{"","0","00","01","-1","+1"," 1","1 ","1\t","1\n","١","１","1١","12345678901234567890","9223372036854775808","9999999999999999999","-9223372036854775808"})
    RejectArguments(new[]{"Binary",candidate,SentinelToken},92);
   foreach(string token in InvalidTokens()) RejectArguments(new[]{"Binary","1",token},token==null?90:92);
   foreach(string token in new[]{new string('0',32),new string('f',32)}) {
    SentinelArguments parsed; int rejection;
    Check(SentinelArguments.TryParse(new[]{"Binary","1",token},out parsed,out rejection) && parsed.Token==token && rejection==0,"entire lowercase ASCII hex range accepted");
   }
   // The actual parser is pure and the result cannot be constructed or mutated by callers.
   Check(typeof(SentinelArguments).GetConstructors().Length==0,"arguments have no public constructor");
   foreach(string property in new[]{"CaseName","Candidate","Token"})
    Check(typeof(SentinelArguments).GetProperty(property,System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic).GetSetMethod(true)==null,"parsed property is immutable: "+property);
   Console.WriteLine("managed sentinel arguments PASS"); return 0;
  }
  static string[] InvalidTokens() {
   return new[]{null,"",new string('a',31),new string('a',33),SentinelToken.ToUpperInvariant()," "+SentinelToken.Substring(1),SentinelToken.Substring(0,31)+" ",
    SentinelToken.Substring(0,31)+"-",SentinelToken.Substring(0,31)+"\\",SentinelToken.Substring(0,31)+"\"",SentinelToken.Substring(0,31)+"\0",SentinelToken.Substring(0,31)+"é",SentinelToken.Substring(0,31)+"ａ",new string('g',32)};
  }
  public static int RunSentinelProtocol() {
   Check(SentinelProtocol.ReferenceName(SentinelToken)=="Local\\pvbox-fixed-sentinel-"+SentinelToken,"fixed reference namespace");
   Check(SentinelProtocol.ReferenceName(new string('0',32))=="Local\\pvbox-fixed-sentinel-"+new string('0',32),"all lowercase hex tokens allowed");
   foreach(string token in InvalidTokens()) { bool rejected=false; try { SentinelProtocol.ReferenceName(token); } catch(ArgumentException) { rejected=true; } Check(rejected,"invalid token refused before APIs"); }
   byte[] expected={80,86,67,50,1,0,0,165};
   byte[] encoded=SentinelProtocol.Encode(SentinelResult.Excluded);
   Check(BitConverter.ToString(encoded)==BitConverter.ToString(expected),"exact PVC2 EXCLUDED bytes");
   byte[] fresh=SentinelProtocol.Encode(SentinelResult.Excluded); encoded[0]=0;
   Check(!Object.ReferenceEquals(encoded,fresh) && fresh[0]==80,"fresh protocol byte arrays");
   foreach(SentinelResult result in new[]{SentinelResult.Unknown,SentinelResult.Excluded,SentinelResult.SameObject}) {
    byte[] bytes=SentinelProtocol.Encode(result);
    Check(bytes.Length==8 && bytes[4]==(byte)result,"each semantic wire value");
    Check(SentinelProtocol.IsExcluded(bytes,8)==(result==SentinelResult.Excluded),"only EXCLUDED may pass");
   }
   foreach(int result in new[]{-1,3,255,256}) { bool rejected=false; try { SentinelProtocol.Encode((SentinelResult)result); } catch(ArgumentOutOfRangeException) { rejected=true; } Check(rejected,"invalid semantic enum refused"); }
   for(int count=-1;count<8;count++) Check(!SentinelProtocol.IsExcluded(expected,count),"truncated or negative count refused");
   Check(!SentinelProtocol.IsExcluded(expected,9) && !SentinelProtocol.IsExcluded(null,8),"count bounded by actual buffer");
   for(int length=0;length<8;length++) Check(!SentinelProtocol.IsExcluded(new byte[length],8),"short backing array refused");
   for(int position=0;position<8;position++) {
    byte[] bad=(byte[])expected.Clone(); bad[position]^=1;
    Check(!SentinelProtocol.IsExcluded(bad,8),"every fixed preamble byte is required");
   }
   byte[] pvc1=(byte[])expected.Clone(); pvc1[3]=49; Check(!SentinelProtocol.IsExcluded(pvc1,8),"PVC1 refused");
   byte[] body=new byte[25]; Array.Copy(expected,body,8); for(int i=8;i<body.Length;i++) body[i]=(byte)(255-i);
   Check(SentinelProtocol.IsExcluded(body,8) && SentinelProtocol.IsExcluded(body,body.Length),"body bytes are not interpreted as preamble");
   Console.WriteLine("managed sentinel protocol PASS"); return 0;
  }
  sealed class SentinelApi : ISentinelQueryApi {
   internal readonly List<string> Calls=new List<string>();
   internal SentinelObserver Observer;
   internal IntPtr Reference=new IntPtr(101);
   internal bool Self=true,Query=true,Same=false,Close=true;
   internal uint OpenError,SelfError,QueryError,CompareError=1656,CloseError;
   internal string Unavailable;
   internal Action<string> AtCall;
   void Enter(string operation,SentinelCallOutcome outcome) {
    Check(outcome==SentinelCallOutcome.ReturnUnavailable,"before-call state: "+operation);
    Check(Observer.Observation.Result==SentinelResult.Unknown,"no semantic success before confirmed close: "+operation);
    if(operation!="open") Check(Observer.Observation.OpenOutcome==SentinelCallOutcome.KnownSuccess && Observer.Observation.OpenError==null,"probe/close follows known acquired reference");
    if(AtCall!=null) AtCall(operation);
    if(Unavailable==operation) throw new InvalidOperationException("fake unavailable return");
   }
   public IntPtr OpenReference(string name,out uint error) {
    Calls.Add("open:"+name); error=OpenError;
    Enter("open",Observer.Observation.OpenOutcome); return Reference;
   }
   public bool QueryHandle(IntPtr handle,out uint flags,out uint error) {
    Calls.Add("query:"+handle.ToInt64()); flags=0xffffffff; error=QueryError;
    Check(Observer.Observation.ProbeStage==SentinelProbeStage.CandidateQuery,"candidate query stage entered");
    Enter("query",Observer.Observation.ProbeOutcome); return Query;
   }
   public bool CompareHandles(IntPtr first,IntPtr second,out uint error) {
    bool self=first==second; string operation=self?"self":"compare";
    Calls.Add(operation+":"+first.ToInt64()+":"+second.ToInt64()); error=self?SelfError:CompareError;
    Check(Observer.Observation.ProbeStage==(self?SentinelProbeStage.ReferenceSelfComparison:SentinelProbeStage.IdentityComparison),"comparison stage entered");
    Enter(operation,Observer.Observation.ProbeOutcome); return self?Self:Same;
   }
   public bool CloseReference(IntPtr reference,out uint error) {
    Calls.Add("close:"+reference.ToInt64()); error=CloseError;
    Check(Observer.HasUnresolvedReference,"owned reference retained until confirmed close");
    Enter("close",Observer.Observation.CloseOutcome); return Close;
   }
  }
  static SentinelObservation Observe(SentinelApi api,string candidate,params string[] operations) {
   api.Observer=new SentinelObserver(Arguments(candidate));
   Check(api.Observer.Observation.OpenOutcome==SentinelCallOutcome.NotEntered && api.Observer.Observation.ProbeOutcome==SentinelCallOutcome.NotEntered && api.Observer.Observation.CloseOutcome==SentinelCallOutcome.NotEntered,"new owner has no native entry");
   SentinelObservation observation=api.Observer.ObserveOnce(api);
   Check(String.Join("|",api.Calls.ToArray())==String.Join("|",operations),"exact query/owned-close call order: "+String.Join("|",api.Calls.ToArray()));
   int calls=api.Calls.Count; Refuses(()=>api.Observer.ObserveOnce(api));
   Check(api.Calls.Count==calls,"repeat refuses before any query or close retry");
   if(observation.CloseOutcome!=SentinelCallOutcome.NotEntered) {
    // No callable cleanup API is exposed. Also exercise the private one-shot
    // guard directly, so even a second internal close attempt cannot retry.
    bool refused=false;
    try { typeof(SentinelObserver).GetMethod("CloseOwnedReferenceOnce",System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic).Invoke(api.Observer,new object[]{api}); }
    catch(System.Reflection.TargetInvocationException error) { refused=error.InnerException is InvalidOperationException; }
    Check(refused && api.Calls.Count==calls,"second close attempt refuses before API entry");
   }
   Check(api.Observer.HasUnresolvedReference==(observation.OpenOutcome==SentinelCallOutcome.ReturnUnavailable || (observation.OpenOutcome==SentinelCallOutcome.KnownSuccess && observation.CloseOutcome!=SentinelCallOutcome.KnownSuccess)),"unresolved acquisition/reference stays on rooted observer");
   return observation;
  }
  static readonly string OpenTrace="open:Local\\pvbox-fixed-sentinel-"+SentinelToken;
  static void Semantic(SentinelObservation observation,SentinelResult result,SentinelReason reason) {
   Check(observation.Result==result && observation.Reason==reason,"semantic result/reason: "+result+"/"+reason);
   Check(SentinelProtocol.IsExcluded(SentinelProtocol.Encode(observation.Result),8)==(result==SentinelResult.Excluded),"semantic result controls preamble");
  }
  public static int RunSentinelObserver() {
   // Baseline different-object observation includes self-check before candidate validity.
   var different=new SentinelApi();
   SentinelObservation observation=Observe(different,"7",OpenTrace,"self:101:101","query:7","compare:7:101","close:101");
   Semantic(observation,SentinelResult.Excluded,SentinelReason.DifferentObject);
   Check(observation.OpenOutcome==SentinelCallOutcome.KnownSuccess && observation.OpenError==null && observation.ProbeStage==SentinelProbeStage.IdentityComparison && observation.ProbeOutcome==SentinelCallOutcome.KnownFailure && observation.ProbeError==1656 && observation.CloseOutcome==SentinelCallOutcome.KnownSuccess && observation.CloseError==null,"different keeps error 1656 after confirmed close");
   var invalid=new SentinelApi {Query=false,QueryError=6};
   observation=Observe(invalid,"7",OpenTrace,"self:101:101","query:7","close:101");
   Semantic(observation,SentinelResult.Excluded,SentinelReason.CandidateInvalidAtQuery);
   Check(observation.ProbeStage==SentinelProbeStage.CandidateQuery && observation.ProbeError==6,"invalid-at-query fact");
   var reused=new SentinelApi {Reference=new IntPtr(7)};
   observation=Observe(reused,"7",OpenTrace,"self:7:7","close:7");
   Semantic(observation,SentinelResult.Excluded,SentinelReason.ReferenceAllocatedAtCandidate);
   Check(observation.ProbeStage==SentinelProbeStage.ReferenceSelfComparison && observation.ProbeError==null,"allocation requires self-test, not candidate query");
   bool parentUnsignaled=true;
   var same=new SentinelApi {Same=true,CompareError=1234,OpenError=5,SelfError=6,QueryError=1656,CloseError=5};
   observation=Observe(same,"7",OpenTrace,"self:101:101","query:7","compare:7:101","close:101");
   Semantic(observation,SentinelResult.SameObject,SentinelReason.SameObject);
   Check(parentUnsignaled && !SentinelProtocol.IsExcluded(SentinelProtocol.Encode(observation.Result),8),"unsignaled parent cannot cure exact SAME");
   Check(observation.OpenError==null && observation.ProbeError==null && observation.CloseError==null && observation.ProbeOutcome==SentinelCallOutcome.KnownSuccess,"success does not capture stale errors");
   foreach(uint error in new uint[]{0,5,6,183,1655,1657,UInt32.MaxValue}) {
    observation=Observe(new SentinelApi {CompareError=error},"7",OpenTrace,"self:101:101","query:7","compare:7:101","close:101");
    Semantic(observation,SentinelResult.Unknown,SentinelReason.Unknown);
    Check(observation.ProbeOutcome==SentinelCallOutcome.KnownFailure && observation.ProbeError==error,"unexpected comparison error retained, including invalidation after query");
   }
   foreach(uint error in new uint[]{0,5,1656,UInt32.MaxValue}) {
    observation=Observe(new SentinelApi {Query=false,QueryError=error},"7",OpenTrace,"self:101:101","query:7","close:101");
    Semantic(observation,SentinelResult.Unknown,SentinelReason.Unknown);
    Check(observation.ProbeError==error,"unexpected validity-query error retained");
   }
   foreach(uint error in new uint[]{0,5,6,1656}) {
    observation=Observe(new SentinelApi {Self=false,SelfError=error},"7",OpenTrace,"self:101:101","close:101");
    Semantic(observation,SentinelResult.Unknown,SentinelReason.Unknown);
    Check(observation.ProbeStage==SentinelProbeStage.ReferenceSelfComparison && observation.ProbeOutcome==SentinelCallOutcome.KnownFailure && observation.ProbeError==error,"unsuccessful self-comparison cannot exclude");
   }
   observation=Observe(new SentinelApi {Reference=new IntPtr(7),Self=false,SelfError=1656},"7",OpenTrace,"self:7:7","close:7");
   Semantic(observation,SentinelResult.Unknown,SentinelReason.Unknown);
   observation=Observe(new SentinelApi {Reference=new IntPtr(7),Unavailable="self"},"7",OpenTrace,"self:7:7","close:7");
   Semantic(observation,SentinelResult.Unknown,SentinelReason.Unknown);
   foreach(uint error in new uint[]{0,2,5,UInt32.MaxValue}) {
    observation=Observe(new SentinelApi {Reference=IntPtr.Zero,OpenError=error},"7",OpenTrace);
    Semantic(observation,SentinelResult.Unknown,SentinelReason.Unknown);
    Check(observation.OpenOutcome==SentinelCallOutcome.KnownFailure && observation.OpenError==error && observation.ProbeStage==SentinelProbeStage.None && observation.ProbeOutcome==SentinelCallOutcome.NotEntered && observation.CloseOutcome==SentinelCallOutcome.NotEntered,"failed open has no fabricated probe or close");
   }
   foreach(string operation in new[]{"open","self","query","compare","close"}) {
    var unavailable=new SentinelApi {Unavailable=operation};
    string[] trace=operation=="open"?new[]{OpenTrace}:operation=="self"?new[]{OpenTrace,"self:101:101","close:101"}:operation=="query"?new[]{OpenTrace,"self:101:101","query:7","close:101"}:new[]{OpenTrace,"self:101:101","query:7","compare:7:101","close:101"};
    observation=Observe(unavailable,"7",trace);
    Semantic(observation,SentinelResult.Unknown,operation=="close"?SentinelReason.DifferentObject:SentinelReason.Unknown);
    if(operation=="open") Check(observation.OpenOutcome==SentinelCallOutcome.ReturnUnavailable && observation.OpenError==null && observation.CloseOutcome==SentinelCallOutcome.NotEntered,"open exception is unknown acquisition");
    else if(operation=="close") Check(observation.CloseOutcome==SentinelCallOutcome.ReturnUnavailable && observation.CloseError==null && observation.ProbeError==1656,"close exception preserves probe, no invented close error");
    else Check(observation.ProbeOutcome==SentinelCallOutcome.ReturnUnavailable && observation.ProbeError==null && observation.CloseOutcome==SentinelCallOutcome.KnownSuccess,"unknown probe still closes owned reference once");
   }
   observation=Observe(new SentinelApi {Close=false,CloseError=5},"7",OpenTrace,"self:101:101","query:7","compare:7:101","close:101");
   Semantic(observation,SentinelResult.Unknown,SentinelReason.DifferentObject);
   Check(observation.ProbeError==1656 && observation.CloseOutcome==SentinelCallOutcome.KnownFailure && observation.CloseError==5,"different and failed close preserve both independent errors");
   foreach(uint closeError in new uint[]{0,5,UInt32.MaxValue}) {
    observation=Observe(new SentinelApi {Same=true,Close=false,CloseError=closeError},"7",OpenTrace,"self:101:101","query:7","compare:7:101","close:101");
    Semantic(observation,SentinelResult.Unknown,SentinelReason.SameObject);
    Check(observation.CloseError==closeError && observation.ProbeError==null,"known SAME and actual failed-close error remain separate");
   }
   observation=Observe(new SentinelApi {Same=true,Unavailable="close"},"7",OpenTrace,"self:101:101","query:7","compare:7:101","close:101");
   Semantic(observation,SentinelResult.Unknown,SentinelReason.SameObject);
   Check(observation.ProbeOutcome==SentinelCallOutcome.KnownSuccess && observation.ProbeError==null && observation.CloseOutcome==SentinelCallOutcome.ReturnUnavailable && observation.CloseError==null,"SAME remains known reason after close uncertainty");
   foreach(bool allocation in new[]{false,true}) foreach(bool throwClose in new[]{false,true}) {
    var failed=new SentinelApi {Query=false,QueryError=6,Reference=new IntPtr(allocation?7:101),Close=false,CloseError=5,Unavailable=throwClose?"close":null};
    observation=allocation?Observe(failed,"7",OpenTrace,"self:7:7","close:7"):Observe(failed,"7",OpenTrace,"self:101:101","query:7","close:101");
    Semantic(observation,SentinelResult.Unknown,allocation?SentinelReason.ReferenceAllocatedAtCandidate:SentinelReason.CandidateInvalidAtQuery);
   }
   var reentrant=new SentinelApi();
   reentrant.AtCall=operation=>{int count=reentrant.Calls.Count;Refuses(()=>reentrant.Observer.ObserveOnce(reentrant));Check(reentrant.Calls.Count==count,"reentrant observation/close retry refused");};
   observation=Observe(reentrant,"9223372036854775807",OpenTrace,"self:101:101","query:9223372036854775807","compare:9223372036854775807:101","close:101");
   Semantic(observation,SentinelResult.Excluded,SentinelReason.DifferentObject);
   bool nullRefused=false; try { new SentinelObserver(null); } catch(ArgumentNullException) { nullRefused=true; } Check(nullRefused,"observer requires a parsed immutable argument");
   var noApi=new SentinelObserver(Arguments("1")); bool noApiRefused=false;
   try { noApi.ObserveOnce(null); } catch(ArgumentNullException) { noApiRefused=true; }
   Check(noApiRefused && noApi.Observation.OpenOutcome==SentinelCallOutcome.NotEntered && !noApi.HasUnresolvedReference,"missing API performs no native entry");
   Refuses(()=>noApi.ObserveOnce(new SentinelApi()));
   Console.WriteLine("managed sentinel observer PASS"); return 0;
  }

  public static int RunManaged() {
   var proof=new ChildCaptureProof();
   proof.UseOnce(); Refuses(proof.UseOnce);
   proof.BeforeCreate(); Refuses(proof.BeforeCreate);
   Check(!proof.CanRelease,"Unknown create return must retain owner");
   proof.CreateReturned(true); Refuses(()=>proof.CreateReturned(false));
   Check(!proof.Complete,"Creation is not exit or EOF");
   proof.ExitObserved=true;
   Check(!proof.Complete,"Child exit without EOF is incomplete");
   proof.StdoutEof=true; Check(!proof.Complete,"One stream EOF is not both streams EOF"); proof.StderrEof=true;
   Check(!proof.Complete,"EOF does not settle pending I/O");
   proof.IoTerminal=true;
   Check(proof.CanRelease && !proof.Complete,"Terminal operations allow close, not complete");
   proof.HandlesClosed=true;
   Check(proof.Complete,"All actual independent facts complete");
   proof.Fault(); Check(proof.Unknown && proof.Complete,"Fault remains unknown after safe release");
   var missing=new ChildCaptureProof(); missing.UseOnce(); missing.BeforeCreate(); missing.Fault();
   missing.ExitObserved=true;missing.IoTerminal=true;missing.HandlesClosed=true;missing.StdoutEof=true;missing.StderrEof=true;
   Check(!missing.CanRelease && !missing.Complete,"Synthetic completion cannot cure missing create return");
   var premature=new ChildCaptureProof(); Refuses(()=>premature.CreateReturned(true)); Refuses(premature.BeforeCreate);
   var rejected=new ChildCaptureProof(); rejected.UseOnce(); rejected.BeforeCreate(); rejected.CreateReturned(false); rejected.IoTerminal=true;
   Check(rejected.CanRelease && !rejected.Complete,"Rejected create can clean but never complete capture");
   var output=new PipeCapture();var bytes=new byte[4096]; bytes[0]=255;
   output.Receive(bytes,4096); output.Fault(1);
   for(int i=0;i<40;i++) output.Receive(bytes,4096);
   Check(output.Unknown && output.Total==167936 && output.RetainedCount==4096 && output.Discarded==163840,"Fault must continue bounded discard");
   var operation=new PipeOperationProof(); operation.BeforeIssue(); operation.CancelReturned(0);
   Check(!operation.SafeToRelease,"Cancellation is not terminal"); operation.ExactTerminal();
   Check(operation.SafeToRelease,"Exact I/O terminal permits storage release");
   var close=new PipeCloseProof(); close.BeforeClose(); close.Returned(false);
   Check(close.Unresolved && !close.Confirmed,"Known failed close is unresolved"); Refuses(close.BeforeClose);
   var lostClose=new PipeCloseProof(); lostClose.BeforeClose();
   Check(lostClose.Unresolved,"Lost close return remains unresolved"); Refuses(lostClose.BeforeClose);
   RunSentinelArguments(); RunSentinelProtocol(); RunSentinelObserver();
   Console.WriteLine("managed fixed-child contracts PASS");return 0;
  }
 }
}
