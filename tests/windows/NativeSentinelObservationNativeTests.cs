// TEST ONLY. Recording boundaries execute the real adapter and parent, never P/Invoke.
using System;
using System.Collections.Generic;
using System.Reflection;
namespace PortableVBox {
 public static class NativeSentinelObservationNativeTests {
  const string Token="0123456789abcdef0123456789abcdef";
  const string Name="Local\\pvbox-fixed-sentinel-"+Token;
  static readonly BindingFlags Fields=BindingFlags.Instance|BindingFlags.NonPublic;
  static void Check(bool value,string message) { if(!value) throw new InvalidOperationException(message); }
  static void Throws(Action action,string message) { bool threw=false;try { action(); } catch(InvalidOperationException) { threw=true; } Check(threw,message); }
  static T Field<T>(ChildCaptureOwner owner,string name) { return (T)typeof(ChildCaptureOwner).GetField(name,Fields).GetValue(owner); }
  static void Trace(List<string> calls,string expected) { Check(String.Join(",",calls.ToArray())==expected,"raw call order expected "+expected+" got "+String.Join(",",calls.ToArray())); }
  sealed class RawQuery : ISentinelQueryNativeCalls {
   internal readonly List<string> Calls=new List<string>();
   internal IntPtr Opened=new IntPtr(101);
   internal bool Query=true,Same=true,Closed=true;
   internal uint Error=1656;
   internal uint? CloseError;
   internal bool? IdentitySame;
   string lastOperation;
   internal string Unavailable;
   internal IntPtr LastFirst,LastSecond,LastClosed;
   internal uint Access;
   internal bool Inherit;
   internal string OpenName;
   void Enter(string call) { Calls.Add(call);if(call!="clear" && call!="capture") lastOperation=call;if(Unavailable==call) throw new EntryPointNotFoundException("fake unavailable "+call); }
   public void ClearLastError() { Enter("clear"); }
   public uint CaptureLastError() { Enter("capture");return lastOperation=="close" && CloseError.HasValue?CloseError.Value:Error; }
   public IntPtr OpenEvent(uint access,bool inherit,string name) { Access=access;Inherit=inherit;OpenName=name;Enter("open");return Opened; }
   public bool GetHandleInformation(IntPtr handle,out uint flags) { LastFirst=handle;flags=0xffffffff;Enter("query");return Query; }
   public bool CompareObjectHandles(IntPtr first,IntPtr second) { LastFirst=first;LastSecond=second;Enter("compare");return first==second?Same:(IdentitySame??Same); }
   public bool CloseHandle(IntPtr handle) { LastClosed=handle;Enter("close");return Closed; }
  }
  static void QueryAdapter() {
   foreach(bool success in new[]{false,true}) {
    var raw=new RawQuery();raw.Opened=success?new IntPtr(101):IntPtr.Zero;
    var api=new NativeSentinelQueryApi(raw);uint error;
    Check(api.OpenReference(Name,out error)==raw.Opened,"real adapter returns raw open");
    Trace(raw.Calls,success?"clear,open":"clear,open,capture");
    Check(raw.Access==0x00100000 && !raw.Inherit && raw.OpenName==Name,"SYNCHRONIZE only, noninheritable, exact fixed name");
    Check(error==(success?0:raw.Error),"open error only captured on failure");
    foreach(string operation in new[]{"query","compare","close"}) {
     raw.Calls.Clear();raw.Query=raw.Same=raw.Closed=success;
     if(operation=="close" && !success) { raw.Opened=new IntPtr(101);api=new NativeSentinelQueryApi(raw);api.OpenReference(Name,out error);raw.Calls.Clear(); }
     bool returned;
     if(operation=="query") { uint flags;returned=api.QueryHandle(new IntPtr(17),out flags,out error);Check(flags==0xffffffff && raw.LastFirst==new IntPtr(17),"query forwards candidate only"); }
     else if(operation=="compare") { returned=api.CompareHandles(new IntPtr(17),new IntPtr(101),out error);Check(raw.LastFirst==new IntPtr(17) && raw.LastSecond==new IntPtr(101),"identity arguments exact"); }
     else { returned=api.CloseReference(new IntPtr(101),out error);Check(raw.LastClosed==new IntPtr(101),"close owns returned reference"); }
     Check(returned==success && error==(success?0:raw.Error),"real "+operation+" return/error");
     Trace(raw.Calls,success?"clear,"+operation:"clear,"+operation+",capture");
    }
   }
   foreach(string operation in new[]{"open","query","compare","close"}) foreach(string unavailable in new[]{"clear",operation,"capture"}) {
    var raw=new RawQuery();var api=new NativeSentinelQueryApi(raw);uint ignored;
    if(operation!="open") api.OpenReference(Name,out ignored);
    raw.Calls.Clear();raw.Opened=IntPtr.Zero;raw.Query=raw.Same=raw.Closed=false;raw.Unavailable=unavailable;
    bool threw=false;
    try {
     if(operation=="open") api.OpenReference(Name,out ignored);
     else if(operation=="query") { uint flags;api.QueryHandle(new IntPtr(17),out flags,out ignored); }
     else if(operation=="compare") api.CompareHandles(new IntPtr(17),new IntPtr(101),out ignored);
     else api.CloseReference(new IntPtr(101),out ignored);
    } catch(EntryPointNotFoundException) { threw=true; }
    Check(threw,"unavailable boundary must propagate: "+operation+"/"+unavailable);
    Trace(raw.Calls,unavailable=="clear"?"clear":unavailable==operation?"clear,"+operation:"clear,"+operation+",capture");
    if(operation=="close") { raw.Calls.Clear();Throws(delegate { api.CloseReference(new IntPtr(101),out ignored); },"close unavailable cannot retry");Check(raw.Calls.Count==0,"no second close boundary entry"); }
   }
   {
    var raw=new RawQuery();var api=new NativeSentinelQueryApi(raw);uint ignored;api.OpenReference(Name,out ignored);raw.Calls.Clear();
    Throws(delegate { api.CloseReference(new IntPtr(17),out ignored); },"borrowed candidate cannot be closed");Check(raw.Calls.Count==0,"borrowed close refused before raw calls");
    api.CloseReference(new IntPtr(101),out ignored);raw.Calls.Clear();Throws(delegate { api.CloseReference(new IntPtr(101),out ignored); },"owned close one-shot");Check(raw.Calls.Count==0,"confirmed close cannot retry");
   }
   foreach(string name in new[]{null,"",Token,"Global\\pvbox-fixed-sentinel-"+Token,"Local\\pvbox-fixed-sentinel-"+Token.ToUpperInvariant(),Name+"0"}) {
    var raw=new RawQuery();var api=new NativeSentinelQueryApi(raw);uint ignored;bool rejected=false;
    try { api.OpenReference(name,out ignored); } catch(ArgumentException) { rejected=true; }
    Check(rejected && raw.Calls.Count==0,"adapter rejects nonfixed name without raw calls");
   }
   {
    var raw=new RawQuery();var api=new NativeSentinelQueryApi(raw);uint ignored;api.OpenReference(Name,out ignored);raw.Calls.Clear();
    Throws(delegate { api.OpenReference(Name,out ignored); },"owned acquisition is one-shot");Check(raw.Calls.Count==0,"repeat open cannot overwrite owned reference");
   }
   // Inspect only declaration metadata: no export probing or native call on this host.
   Type native=typeof(NativeSentinelQueryApi).Assembly.GetType("PortableVBox.SentinelNativeCalls",true);
   var declaration=(System.Runtime.InteropServices.DllImportAttribute)Attribute.GetCustomAttribute(native.GetMethod("CompareObjectHandles",BindingFlags.Static|BindingFlags.NonPublic),typeof(System.Runtime.InteropServices.DllImportAttribute));
   Check(declaration!=null && declaration.Value=="Kernelbase.dll" && declaration.SetLastError && declaration.ExactSpelling,"documented comparison export with last-error capture");
   Type security=native.GetNestedType("SecurityAttributes",BindingFlags.NonPublic);
   Check(System.Runtime.InteropServices.Marshal.SizeOf(security)==24 && System.Runtime.InteropServices.Marshal.OffsetOf(security,"Descriptor").ToInt32()==8 && System.Runtime.InteropServices.Marshal.OffsetOf(security,"Inherit").ToInt32()==16,"exact x64 SECURITY_ATTRIBUTES layout");
   foreach(string method in new[]{"OpenEventW","CreateEventW"}) {
    var import=(System.Runtime.InteropServices.DllImportAttribute)Attribute.GetCustomAttribute(native.GetMethod(method,BindingFlags.Static|BindingFlags.NonPublic),typeof(System.Runtime.InteropServices.DllImportAttribute));
    Check(import.SetLastError && import.ExactSpelling && import.CharSet==System.Runtime.InteropServices.CharSet.Unicode,"fixed Unicode entry and last-error preservation");
   }
  }
  static void ObserverAdapterComposition() {
   foreach(string mode in new[]{"allocated","invalid","different","same","changed","unexpected","self-unavailable","close-false","close-unavailable"}) {
    var raw=new RawQuery();raw.IdentitySame=mode=="same";
    if(mode=="invalid") { raw.Query=false;raw.Error=6; }
    if(mode=="changed") raw.Error=6;
    if(mode=="unexpected") raw.Error=0;
    if(mode=="self-unavailable") raw.Unavailable="compare";
    if(mode=="close-false") { raw.Closed=false;raw.CloseError=5; }
    if(mode=="close-unavailable") raw.Unavailable="close";
    SentinelArguments parsed;int rejection;
    Check(SentinelArguments.TryParse(new[]{"Binary",mode=="allocated"?"101":"17",Token},out parsed,out rejection),"actual composition arguments");
    var observer=new SentinelObserver(parsed);var api=new NativeSentinelQueryApi(raw);SentinelObservation result=observer.ObserveOnce(api);
    SentinelResult expected=mode=="allocated" || mode=="invalid" || mode=="different"?SentinelResult.Excluded:mode=="same"?SentinelResult.SameObject:SentinelResult.Unknown;
    Check(result.Result==expected,"real observer/adapter composition "+mode);
    Check(raw.LastClosed==new IntPtr(101),"real composition closes only acquired reference "+mode);
    if(mode=="allocated") { Check(result.Reason==SentinelReason.ReferenceAllocatedAtCandidate,"allocation role is not inherited-object equality");Trace(raw.Calls,"clear,open,clear,compare,clear,close"); }
    if(mode=="invalid") { Check(result.Reason==SentinelReason.CandidateInvalidAtQuery && result.ProbeError==6,"invalid at query remains precise");Trace(raw.Calls,"clear,open,clear,compare,clear,query,capture,clear,close"); }
    if(mode=="different") { Check(result.ProbeError==1656 && result.CloseError==null,"strict explicit mismatch and successful close");Trace(raw.Calls,"clear,open,clear,compare,clear,query,clear,compare,capture,clear,close"); }
    if(mode=="changed" || mode=="unexpected") Check(result.Reason==SentinelReason.Unknown && result.ProbeError==raw.Error,"no widened false-comparison acceptance");
    if(mode=="self-unavailable") Check(result.ProbeOutcome==SentinelCallOutcome.ReturnUnavailable && result.ProbeError==null,"missing comparison API remains unknown");
    if(mode=="close-false") Check(result.Reason==SentinelReason.DifferentObject && result.ProbeError==1656 && result.CloseError==5 && observer.HasUnresolvedReference,"probe/close errors remain independent through actual adapter");
    if(mode=="close-unavailable") Check(result.CloseOutcome==SentinelCallOutcome.ReturnUnavailable && result.CloseError==null && observer.HasUnresolvedReference,"unavailable real-adapter close retained");
    raw.Calls.Clear();Throws(delegate { observer.ObserveOnce(api); },"composed observer one-shot");Check(raw.Calls.Count==0,"no composed retry");
   }
  }
  sealed class RawFresh : IFreshSentinelNativeCalls {
   internal readonly List<string> Calls=new List<string>();
   internal IntPtr Created=new IntPtr(201),Descriptor,ClosedHandle;
   internal string Name,Unavailable;
   internal bool Manual,Initial,Inherit,Flag=true,Closed=true;
   internal uint Error,Mask,Flags;
   internal Action<string> AtCall;
   void Enter(string call) { Calls.Add(call);if(AtCall!=null) AtCall(call);if(Unavailable==call) throw new EntryPointNotFoundException("fake unavailable "+call); }
   public void ClearLastError() { Enter("clear"); }
   public uint CaptureLastError() { Enter("capture");return Error; }
   public IntPtr CreateEvent(IntPtr descriptor,bool manual,bool initial,bool inherit,string name) { Descriptor=descriptor;Manual=manual;Initial=initial;Inherit=inherit;Name=name;Enter("create");return Created; }
   public bool SetHandleInformation(IntPtr handle,uint mask,uint flags) { Check(handle==Created,"only parent owned sentinel flags");Mask=mask;Flags=flags;Enter("flag");return Flag; }
   public bool CloseHandle(IntPtr handle) { ClosedHandle=handle;Enter("close");return Closed; }
  }
  static void RefusedLaunch(ChildCaptureOwner owner) {
   bool refused=false;
   try { typeof(ChildCaptureOwner).GetMethod("Launch",Fields).Invoke(owner,null); }
   catch(TargetInvocationException error) { refused=error.InnerException is InvalidOperationException && error.InnerException.Message=="Fresh sentinel required"; }
   Check(refused && owner.CreateCalls==0 && Field<System.IO.FileStream>(owner,"imageLease")==null,"actual Launch readiness guard before files or CreateProcess");
  }
  static void RepeatPreparation(ChildCaptureOwner owner,RawFresh raw) {
   raw.Calls.Clear();Throws(delegate { owner.PrepareFreshSentinel(new IntPtr(73)); },"fresh preparation is one-shot");Check(raw.Calls.Count==0,"repeat before clear/create/flags");
  }
  static void FreshParent() {
   {
    var raw=new RawFresh();var owner=new ChildCaptureOwner(CaptureCase.Binary,raw);RefusedLaunch(owner);
    raw.AtCall=delegate(string call) { Check(!owner.SentinelReady,"not ready before flag return");if(call=="capture") Check(Field<IntPtr>(owner,"sentinel")==raw.Created,"returned handle rooted before Create error capture"); };
    owner.PrepareFreshSentinel(new IntPtr(73));Trace(raw.Calls,"clear,create,capture,clear,flag");
    Check(owner.SentinelReady && !owner.Unknown,"known fresh flags success alone sets readiness");
    Check(owner.SentinelCreateOutcome==SentinelCallOutcome.KnownSuccess && owner.SentinelCreateError==0 && owner.SentinelFlagOutcome==SentinelCallOutcome.KnownSuccess && owner.SentinelFlagError==null,"fresh creation error observed, success flags ignore stale error");
    Check(raw.Descriptor==new IntPtr(73) && raw.Manual && !raw.Initial && !raw.Inherit,"exact private descriptor and event flags");
    Check(raw.Name.StartsWith("Local\\pvbox-fixed-sentinel-",StringComparison.Ordinal) && SentinelProtocol.ValidToken(raw.Name.Substring("Local\\pvbox-fixed-sentinel-".Length)),"only reconstructed generated fixed namespace");
    Check(raw.Name==SentinelProtocol.ReferenceName(Field<string>(owner,"sentinelToken")) && raw.Mask==1 && raw.Flags==1,"generated token and exact inheritance flag tuple");
    RepeatPreparation(owner,raw);raw.AtCall=delegate { Check(!owner.SentinelReady,"close entry revokes readiness"); };
    owner.CloseSentinel();Trace(raw.Calls,"clear,close");Check(raw.ClosedHandle==raw.Created && Field<IntPtr>(owner,"sentinel")==IntPtr.Zero,"known close clears owned sentinel");
    Check(owner.SentinelCloseOutcome==SentinelCallOutcome.KnownSuccess && owner.SentinelCloseError==null,"known close does not capture stale error");
    raw.Calls.Clear();owner.CloseSentinel();Check(raw.Calls.Count==0,"no second known close");RefusedLaunch(owner);
   }
   foreach(uint error in new uint[]{0,5,183}) foreach(bool returned in new[]{false,true}) {
    if(returned && error!=183) continue;
    var raw=new RawFresh();raw.Created=returned?new IntPtr(201):IntPtr.Zero;raw.Error=error;
    var owner=new ChildCaptureOwner(CaptureCase.Binary,raw);
    Throws(delegate { owner.PrepareFreshSentinel(new IntPtr(73)); },"NULL/existing creation refusal");
    Trace(raw.Calls,returned?"clear,create,capture,clear,close":"clear,create,capture");
    Check(!owner.SentinelReady && owner.Unknown && !raw.Calls.Contains("flag"),"refusal before inheritance mutation");
    Check(owner.SentinelCreateError==error && owner.SentinelCreateOutcome==(returned?SentinelCallOutcome.KnownSuccess:SentinelCallOutcome.KnownFailure),"creation return and error captured even with non-NULL");
    Check(owner.SentinelFlagOutcome==SentinelCallOutcome.NotEntered && owner.SentinelFlagError==null,"refused freshness never enters flags");
    RepeatPreparation(owner,raw);owner.CloseSentinel();Check(raw.Calls.Count==0,"no repeated collision cleanup");RefusedLaunch(owner);
   }
   foreach(string unavailable in new[]{"clear","create","capture","flag"}) {
    var raw=new RawFresh();raw.Unavailable=unavailable;var owner=new ChildCaptureOwner(CaptureCase.Binary,raw);
    bool threw=false;try { owner.PrepareFreshSentinel(new IntPtr(73)); } catch(EntryPointNotFoundException) { threw=true; }
    Check(threw && !owner.SentinelReady && owner.Unknown,"unavailable create/capture/flags retain UNKNOWN");
    Check(Field<bool>(owner,"nativeOutcomeUnknown"),"unavailable boundary remains return unknown");
    Check((unavailable=="flag"?owner.SentinelFlagOutcome:owner.SentinelCreateOutcome)==SentinelCallOutcome.ReturnUnavailable,"entered stage has no fabricated known return/error");
    Check(owner.SentinelFlagError==null && owner.SentinelCloseOutcome==SentinelCallOutcome.NotEntered,"unavailable freshness retains no later success");
    if(unavailable=="capture" || unavailable=="flag") Check(Field<IntPtr>(owner,"sentinel")==raw.Created,"acquired handle retained after uncertain capture/flag return");
    RepeatPreparation(owner,raw);owner.CloseSentinel();Check(raw.Calls.Count==0,"uncertain acquisition/flags cannot be cleaned speculatively");RefusedLaunch(owner);
   }
   {
    var raw=new RawFresh();raw.Flag=false;raw.Error=5;var owner=new ChildCaptureOwner(CaptureCase.Binary,raw);
    Throws(delegate { owner.PrepareFreshSentinel(new IntPtr(73)); },"FALSE inheritance cannot set readiness");
    Trace(raw.Calls,"clear,create,capture,clear,flag,capture,clear,close");Check(!owner.SentinelReady && owner.Unknown,"FALSE flags remain unknown");
    Check(owner.SentinelFlagOutcome==SentinelCallOutcome.KnownFailure && owner.SentinelFlagError==5 && owner.SentinelCreateError==5 && owner.SentinelCloseError==null,"flag failure preserves distinct observed errors");RefusedLaunch(owner);
   }
   for(int unavailableEntry=1;unavailableEntry<=6;unavailableEntry++) {
    var raw=new RawFresh();raw.Flag=unavailableEntry!=6;var owner=new ChildCaptureOwner(CaptureCase.Binary,raw);int entries=0;
    raw.AtCall=delegate(string call) {
     Check(Field<bool>(owner,"nativeOutcomeUnknown") && !owner.SentinelReady,"parent records unknown before every raw boundary");
     Check((entries<3?owner.SentinelCreateOutcome:owner.SentinelFlagOutcome)==SentinelCallOutcome.ReturnUnavailable,"parent stage entered before clear/native/capture");
     if(++entries==unavailableEntry) throw new EntryPointNotFoundException("precise unavailable boundary");
    };
    bool threw=false;try { owner.PrepareFreshSentinel(new IntPtr(73)); } catch(EntryPointNotFoundException) { threw=true; }
    Check(threw && entries==unavailableEntry && owner.Unknown && !owner.SentinelReady,"exact unavailable freshness boundary retained");
    Check(owner.SentinelCloseOutcome==SentinelCallOutcome.NotEntered,"uncertainty forbids speculative cleanup");
    raw.AtCall=null;raw.Calls.Clear();owner.CloseSentinel();typeof(ChildCaptureOwner).GetMethod("Release",Fields).Invoke(owner,null);
    Check(raw.Calls.Count==0 && !owner.Released,"no speculative close/release after unavailable capture");RefusedLaunch(owner);
   }
   foreach(bool collision in new[]{false,true}) foreach(string failure in new[]{"false","clear","close","capture"}) {
    var raw=new RawFresh();var owner=new ChildCaptureOwner(CaptureCase.Binary,raw);
    if(!collision) owner.PrepareFreshSentinel(new IntPtr(73));
    raw.Calls.Clear();raw.Error=collision?183U:5U;raw.Closed=failure!="false" && failure!="capture";
    raw.Unavailable=failure=="false"?null:failure;
    if(collision && (failure=="clear" || failure=="capture")) {
     // Inject only at cleanup, after the unconditional Create error capture.
     raw.Unavailable=null;raw.AtCall=delegate(string call) { if(call=="close" && failure=="capture") raw.Unavailable="capture";if(call=="capture" && !Field<PipeCloseProof>(owner,"sentinelClose").Attempted) raw.Unavailable=failure=="clear"?"clear":null; };
    }
    bool threw=false;
    try { if(collision) owner.PrepareFreshSentinel(new IntPtr(73));else owner.CloseSentinel(); } catch(Exception) { threw=true; }
    Check(threw && !owner.SentinelReady && owner.Unknown && Field<IntPtr>(owner,"sentinel")==raw.Created,"unresolved parent close retains owned handle and revokes readiness");
    PipeCloseProof proof=Field<PipeCloseProof>(owner,"sentinelClose");Check(proof.Attempted && proof.Unresolved && !proof.Confirmed,"unresolved original close proof");
    Check(owner.SentinelCloseOutcome==(failure=="false"?SentinelCallOutcome.KnownFailure:SentinelCallOutcome.ReturnUnavailable),"false versus unavailable close remains distinct");
    Check(owner.SentinelCloseError==(failure=="false"?(uint?)(collision?183U:5U):null),"close error never fabricated and independent of create error");
    raw.AtCall=null;raw.Unavailable=null;raw.Calls.Clear();owner.CloseSentinel();
    typeof(ChildCaptureOwner).GetMethod("Release",Fields).Invoke(owner,null);
    Check(raw.Calls.Count==0 && !owner.Released,"no retry through CloseSentinel or actual Release");RefusedLaunch(owner);
   }
  }
  public static int RunCapturedSentinel() {
   var expected=typeof(NativeChildCaptureNativeTests).GetMethod("Expected",BindingFlags.Static|BindingFlags.NonPublic);
   int[] lengths={0,17,4097,196731,257,204829};
   ulong[] hashes={0xcbf29ce484222325UL,0xe6a7f5deb30873c0UL,0x031381f5c4fbe740UL,0xc1f1accadf2339e9UL,0xc98455caf71ceb86UL,0x8b07499bc23a9f3eUL};
   for(int i=0;i<lengths.Length;i++) Check((ulong)expected.Invoke(null,new object[]{lengths[i],i>=4?71:0,i>0 && i<4})==hashes[i],"independent Expected literal PVC2/stdout/stderr hash "+i);
   foreach(byte semantic in new byte[]{0,1,2}) {
    var owner=new ChildCaptureOwner(CaptureCase.Binary,new RawFresh());
    byte[] header={80,86,67,50,semantic,0,0,165};owner.Channels[0].Capture.Receive(header,header.Length);
    byte[] bytes=new byte[4096];
    for(int offset=0;offset<4097;offset+=4096) {
     int count=Math.Min(bytes.Length,4097-offset);
     for(int i=0;i<count;i++) bytes[i]=(byte)(((offset+i)*31)&255);
     owner.Channels[0].Capture.Receive(bytes,count);
    }
    byte[] stderr=new byte[257];for(int i=0;i<stderr.Length;i++) stderr[i]=(byte)((i*31+71)&255);
    owner.Channels[1].Capture.Receive(stderr,stderr.Length);
    owner.Channels[0].Capture.ObserveEof();owner.Channels[1].Capture.ObserveEof();owner.Proof.ExitObserved=true;owner.ExitCode=0;
    Check(owner.Channels[0].Capture.Total==4105 && owner.Channels[1].Capture.Total==257 && owner.Channels[1].Capture.Hash==0xc98455caf71ceb86UL,"complete Binary stdout/stderr fixture before sentinel assertion");
    if(semantic==1) Check(owner.Channels[0].Capture.Hash==0x031381f5c4fbe740UL,"complete Binary PVC2 stdout hash");
    Check(owner.CapturedSentinelExcluded()==(semantic==1),"actual capture only accepts EXCLUDED despite correct body, EOF, normal exit");
   }
   for(int invalid=0;invalid<9;invalid++) {
    var owner=new ChildCaptureOwner(CaptureCase.Binary,new RawFresh());byte[] bytes={80,86,67,50,1,0,0,165};
    if(invalid<8) bytes[invalid]^=1;
    owner.Channels[0].Capture.Receive(bytes,invalid==8?7:8);owner.Proof.ExitObserved=true;owner.ExitCode=0;
    Check(!owner.CapturedSentinelExcluded(),"actual capture rejects every corrupted or truncated prefix");
   }
   foreach(uint exit in new uint[]{0,23,93,94,259}) foreach(bool observed in new[]{false,true}) {
    var owner=new ChildCaptureOwner(CaptureCase.Empty,new RawFresh());owner.ExitCode=exit;owner.Proof.ExitObserved=observed;
    Check(owner.CapturedSentinelExcluded()==(observed && exit==0),"dedicated Empty exit inference");
   }
   Console.WriteLine("managed sentinel capture composition PASS");return 0;
  }
  public static int RunQueryAdapter() { QueryAdapter();ObserverAdapterComposition();Console.WriteLine("managed sentinel query adapter PASS");return 0; }
  public static int RunFreshParent() { FreshParent();Console.WriteLine("managed sentinel fresh parent PASS");return 0; }
  public static int RunManaged() {
   QueryAdapter();ObserverAdapterComposition();FreshParent();RunCapturedSentinel();Console.WriteLine("managed sentinel native adapter PASS");return 0;
  }
 }
}
