// TEST ONLY: pure ledgers and real owners with recording calls, no uncertain OS calls.
using System;
using System.Security.Cryptography;
using System.Text;
namespace PortableVBox {
 public static class NativeFixedImageIdentityTests {
  static void Check(bool value,string name) { if(!value)throw new Exception("ASSERT fixed image: "+name); }
  static void Reject(Action action,string name) { bool refused=false;try { action(); } catch(ArgumentException) { refused=true; } catch(InvalidOperationException) { refused=true; }Check(refused,name); }
  static string Digest(byte[] bytes) { using(var sha=SHA256.Create())return FixedImageCodec.Hex(sha.ComputeHash(bytes)); }
  static FixedImageState Open(long length) { var s=new FixedImageState(new FixedImageExpectation(length,new string('a',64)));s.EnterOpen();s.ReturnOpen(true,null);s.ObserveSize(length);return s; }
  static void Read(FixedImageState s,int request,uint count) { s.EnterRead(request);s.ReturnRead(true,count,null);if(count>0 && count<=request && s.EofRequestBytes==null)s.AcceptHashed((int)count); }
  public static string IncompleteReport(int mode) {
   var s=Open(17);s.ObserveIdentity(true,0,1,2);s.ObservePath("C:\\fixture",10);
   if(mode==0) { Read(s,17,3);Read(s,14,0); }
   else { Read(s,17,17);Read(s,1,mode==1?1U:0U);if(mode==2)s.HashFailed(); }
   s.EnterClose();s.ReturnClose(true);
   return FixedImageEvidence.Report(s.Expected,s.Snapshot(),"matching-image",false,"null","null");
  }
  public static string UnicodeReport() {
   var s=Open(17);
   string path="C:\\Привет\\漢字-é-\U0001f642\\NativeCaptureFixtureChild.exe";
   s.ObserveIdentity(true,0,1,2);
   s.ObservePath(path,(uint)path.Length);
   Read(s,17,17);
   Read(s,1,0);
   s.CompleteHash(new string('a',64));
   s.EnterClose();s.ReturnClose(true);
   var denied=new FixedImageProbeState();denied.EnterOpen();denied.ReturnOpen(false,32);
   string write=denied.Json(new FixedImageProbeCall(0x40000000,7,3));
   string delete=denied.Json(new FixedImageProbeCall(0x10000,7,3));
   return FixedImageEvidence.Report(s.Expected,s.Snapshot(),"matching-image",true,write,delete);
  }
  static void ProbeContracts() {
   var unopened=new FixedImageProbeState();
   Check(unopened.OpenState=="not-entered" && unopened.CloseState=="not-opened" && unopened.OpenError==null,"probe initially unavailable");
   Reject(delegate { unopened.ReturnOpen(false,32); },"probe return requires open entry");
   Reject(delegate { unopened.EnterClose(); },"unopened probe cannot close");
   unopened.EnterOpen();
   Check(unopened.OpenState=="return-unknown" && !unopened.Resolved && !unopened.CanClose,"unknown probe open retains owner");
   Reject(delegate { unopened.EnterOpen(); },"unknown probe open cannot retry");
   Reject(delegate { unopened.EnterClose(); },"unknown probe open cannot close");
   Reject(delegate { unopened.ReturnClose(true); },"probe close return requires entry");
   foreach(uint error in new uint[] {32,2}) {
    var failed=new FixedImageProbeState();
    failed.EnterOpen();failed.ReturnOpen(false,error);
    Check(failed.Resolved && failed.Denied==(error==32) && failed.OpenError==error && failed.CloseState=="not-opened","known failed probe owns no handle");
    Reject(delegate { failed.EnterOpen(); },"failed probe open cannot retry");
    Reject(delegate { failed.EnterClose(); },"failed probe open cannot close");
    Reject(delegate { failed.ReturnOpen(false,error); },"probe open return cannot repeat");
   }
   var unknownClose=new FixedImageProbeState();
   unknownClose.EnterOpen();unknownClose.ReturnOpen(true,null);
   Check(unknownClose.CanClose && !unknownClose.Resolved && !unknownClose.Denied,"unexpected probe success requires checked close");
   unknownClose.EnterClose();
   Check(unknownClose.CloseState=="return-unknown" && !unknownClose.Resolved && !unknownClose.CanClose,"unknown probe close retains owner");
   Reject(delegate { unknownClose.EnterClose(); },"unknown probe close cannot retry");
   Reject(delegate { unknownClose.EnterOpen(); },"unknown probe close cannot reopen");
   foreach(bool success in new bool[] {false,true}) {
    var closed=new FixedImageProbeState();
    closed.EnterOpen();closed.ReturnOpen(true,null);closed.EnterClose();closed.ReturnClose(success);
    Check(closed.CloseState==(success?"returned-success":"returned-failure") && closed.Resolved==success && !closed.CanClose,"only TRUE probe close resolves ownership");
    Reject(delegate { closed.EnterClose(); },"known probe close never retries");
    Reject(delegate { closed.EnterOpen(); },"known probe close cannot reopen");
    Reject(delegate { closed.ReturnClose(success); },"probe close return cannot repeat");
   }
   var invalid=new FixedImageProbeState();invalid.EnterOpen();
   Reject(delegate { invalid.ReturnOpen(true,32); },"successful probe cannot invent error");
   Check(invalid.OpenState=="return-unknown" && invalid.OpenError==null && !invalid.Resolved,"invalid probe return retains uncertainty");
  }
  public static string ProbeFaultReport(int mode) {
   var image=Open(17);image.ObserveIdentity(true,0,1,2);image.ObservePath("C:\\fixture",10);
   Read(image,17,17);Read(image,1,0);image.CompleteHash(new string('a',64));
   var probe=new FixedImageProbeState();probe.EnterOpen();
   if(mode>0) {
    probe.ReturnOpen(true,null);probe.EnterClose();
    if(mode==2)probe.ReturnClose(false);
   }
   return FixedImageEvidence.Report(image.Expected,image.Snapshot(),"matching-image",false,
       probe.Json(new FixedImageProbeCall(0x40000000,7,3)),"null");
  }
  static void PathContracts() {
   foreach(string raw in new string[] {"C:\\", "z:\\file", @"\\?\C:\fixed", "C:\\Привет\\漢字-é-\U0001f642", "C:\\a/../b ", "C:\\"+new string('x',32764), "C:\\"+new string('x',32762)+"\U0001f642"}) {
    Check(Object.ReferenceEquals(FixedImagePath.Validate(raw),raw),"supported path raw units unchanged");
    Check(FixedImageCodec.LocalPath(raw)==raw,"held image consumes shared path validation");
    Check(FixedImagePath.Agree(raw,raw),"identical paths agree");
   }
   foreach(string raw in new string[] {null,"",@"\\server\share",@"\\?\UNC\server\share",@"\\.\C:\file",@"\\?\Volume{abc}\file",@"\\?\\\?\C:\file","C:relative","C:/slash",@"\root","/root","C:\\bad\ud800","C:\\bad\udc00","C:\\"+new string('x',32765),"C:\\"+new string('x',32763)+"\U0001f642"}) {
    Reject(delegate { FixedImagePath.Validate(raw); },"unsupported grammar/UTF16/bound");
    Reject(delegate { FixedImagePath.Comparable(raw); },"comparable always validates");
    Reject(delegate { FixedImagePath.Agree("C:\\x",raw); },"comparison always validates");
   }
   for(int i=0;i<=159;i++)if(i<=31 || i>=127) {
    string raw="C:\\bad"+(char)i+"path";
    Reject(delegate { FixedImagePath.Validate(raw); },"all C0/DEL/C1 rejected");
    Reject(delegate { FixedImageCodec.LocalPath(raw); },"image codec uses shared Cc rejection");
   }
   Check(FixedImagePath.Comparable(@"\\?\C:\Fixed")==@"C:\Fixed","only exact DOS prefix removed");
   Check(FixedImagePath.Agree(@"\\?\C:\Fixed",@"c:\fixed"),"prefix and ASCII case agreement");
   Check(FixedImagePath.Agree("C:\\Привет-漢字-\U0001f642-A","c:\\Привет-漢字-\U0001f642-a"),"unchanged nonASCII with ASCII-only case");
   foreach(string[] pair in new string[][] {
    new string[] {@"C:\a/b",@"C:\a\b"},new string[] {@"C:\a\..\b",@"C:\b"},
    new string[] {"C:\\Straße","C:\\STRASSE"},new string[] {"C:\\é","C:\\e\u0301"},
    new string[] {@"C:\x",@"C:\y"},new string[] {@"C:\x",@"C:\x "}})
    Check(!FixedImagePath.Agree(pair[0],pair[1]),"different spelling not normalized");
   // This managed host's result is not evidence of Windows Framework execution.
   Check(FixedImagePath.Agree("C:\\é","C:\\É"),"actual managed OrdinalIgnoreCase nonASCII call");
  }
  sealed class Unavailable : Exception { }
  // The only fake handles in these tests belong to this adapter. No OS handle is
  // acquired; every downstream boundary checks the exact owned recording handle.
  sealed class RecordingFileCalls : IFixedImageNativeCalls {
   readonly FixedImageCallDomain domain;
   readonly byte[] bytes;
   internal readonly System.Collections.Generic.List<string> Trace=new System.Collections.Generic.List<string>();
   internal string Fault="";
   internal long Size;
   internal int PartialLimit=997;
   internal Action BeforeClose=null;
   int position,probe;
   bool errorPending;
   uint error;
   internal RecordingFileCalls(byte[] pristine,FixedImageCallDomain domain) {
    this.domain=domain;bytes=(byte[])pristine.Clone();Size=bytes.Length;
   }
   public FixedImageCallDomain Domain { get { return domain; } }
   void Enter(string operation) {
    Check(!errorPending,"last error must be captured before next call");Trace.Add(operation);
    if(Fault==operation+"-unavailable")throw new Unavailable();
   }
   void Fail(uint code) { errorPending=true;error=code; }
   public uint CaptureLastError() { Check(errorPending,"capture only immediately after failed return");Trace.Add("error");errorPending=false;return error; }
   void Image(IntPtr handle) { Check(handle==new IntPtr(201),"exact image handle at every query/read"); }
   public IntPtr CreateFileW(string name,uint access,uint share,IntPtr security,uint disposition,uint flags,IntPtr template) {
    Check(System.IO.Path.GetFileName(name)=="NativeCaptureFixtureChild.exe" && System.IO.Path.GetDirectoryName(name)==System.IO.Path.GetDirectoryName(typeof(NativeFixedImageIdentityTests).Assembly.Location),"fixed sibling only");
    Check(security==IntPtr.Zero && template==IntPtr.Zero && disposition==3,"noninheritable open-existing only");
    if(access==0x80000000) {
     Check(share==1 && flags==0x00200000,"image read/share-read/reparse-leaf refusal");Enter("open");
     if(Fault=="open-false") { Fail(2);return new IntPtr(-1); }
     return new IntPtr(201);
    }
    Check((access==0x40000000 || access==0x10000) && share==7 && flags==0,"exact compatible probe access/share/disposition");
    ++probe;Check(access==(probe==1?0x40000000U:0x10000U),"write then delete probe order");Enter("probe"+probe);
    if(Fault=="probe-success" || Fault=="probe-close-false" || Fault=="probe-close-unavailable")return new IntPtr(300+probe);
    Fail(Fault=="probe-error"?5U:32U);return new IntPtr(-1);
   }
   public bool Attributes(IntPtr handle,int info,out FixedImageNative.AttributeTag value,uint size) {
    Image(handle);Check(info==9 && size==8,"exact attribute query");Enter("attributes");value=new FixedImageNative.AttributeTag();value.Attributes=0x80;
    if(Fault=="attributes-false") { Fail(5);return false; }return true;
   }
   public bool GetFileSizeEx(IntPtr handle,out long size) {
    Image(handle);Enter("size");size=Size;if(Fault=="size-false") { Fail(5);return false; }return true;
   }
   public bool Identity(IntPtr handle,int info,out FixedImageNative.IdInfo value,uint size) {
    Image(handle);Check(info==18 && size==24,"exact 128-bit identity query");Enter("identity");value=new FixedImageNative.IdInfo();value.Volume=0;value.Low=1;value.High=2;
    if(Fault=="identity-false") { Fail(5);return false; }return true;
   }
   public uint GetFinalPathNameByHandleW(IntPtr handle,StringBuilder buffer,uint length,uint flags) {
    Image(handle);Check(length==32768 && buffer.Capacity==32768 && flags==0,"bounded normalized DOS path query");Enter("path");
    if(Fault=="path-false") { Fail(5);return 0; }
    buffer.Append("C:\\fixture\\NativeCaptureFixtureChild.exe");return (uint)buffer.Length;
   }
   public bool ReadFile(IntPtr handle,byte[] target,uint request,out uint read,IntPtr overlapped) {
    Image(handle);Check(overlapped==IntPtr.Zero && request>0 && request<=65536 && target.Length==65536,"bounded synchronous positive read");
    Enter(position==bytes.Length?"eof":"read");read=0;
    if(Fault=="read-false" || (Fault=="eof-false" && position==bytes.Length)) { Fail(5);return false; }
    if(position==bytes.Length) {
     Check(request==1,"positive one-byte EOF proof after exact bytes");
     if(Fault=="extra")read=1;return true;
    }
    Check(request==Math.Min(65536,bytes.Length-position),"exact bounded remaining read request");
    if(Fault=="early")return true;
    if(Fault=="oversize") { read=request+1;return true; }
    read=(uint)Math.Min(PartialLimit,(int)request);Array.Copy(bytes,position,target,0,(int)read);position+=(int)read;return true;
   }
   public bool CloseHandle(IntPtr handle) {
    bool image=handle==new IntPtr(201);
    Check(image || handle==new IntPtr(301) || handle==new IntPtr(302),"only exact owned image/probe handles may close");
    Enter(image?"close":"probe-close");if(BeforeClose!=null)BeforeClose();
    if(Fault==(image?"close-false":"probe-close-false")) { Fail(6);return false; }return true;
   }
  }
  static RecordingFileCalls Calls(byte[] bytes) { return new RecordingFileCalls(bytes,FixedImageCallDomain.CreateRecording()); }
  static FixedFixtureImage Image(RecordingFileCalls calls) { return FixedFixtureImage.CreateForRecording(calls,calls.Domain); }
  static void ExactTrace(RecordingFileCalls calls,params string[] expected) { Check(String.Join(",",calls.Trace.ToArray())==String.Join(",",expected),"exact real-owner call order: "+String.Join(",",calls.Trace.ToArray())); }
  static byte[] VerifiedPristine(byte[] input) {
   if(input==null)throw new ArgumentException("Genuine completed pristine child bytes required");
   byte[] copy=(byte[])input.Clone();
   if(copy.LongLength!=FixedFixtureBuildExpectation.Length || Digest(copy)!=FixedFixtureBuildExpectation.Sha256)throw new ArgumentException("Genuine completed pristine child bytes required");
   return copy;
  }
  static void ClaimRejectsPreparedReleasedAndReused(byte[] bytes) {
   var calls=Calls(bytes);var fresh=Image(calls);
   Reject(delegate { FixedFixtureImage.CreateForRecording(null,calls.Domain); },"null adapter");
   Reject(delegate { FixedFixtureImage.CreateForRecording(calls,null); },"null domain");
   Reject(delegate { FixedFixtureImage.CreateForRecording(calls,FixedImageCallDomain.CreateRecording()); },"wrong recording domain");
   Reject(delegate { FixedFixtureImage.CreateForRecording(calls,FixedImageCallDomain.Native); },"recording/native domain mismatch");
   Reject(delegate { FixedFixtureImage.CreateForRecording(FixedImageNativeCalls.Instance,FixedImageCallDomain.Native); },"native adapter forbidden in recording factory");
   var forgedNative=new RecordingFileCalls(bytes,FixedImageCallDomain.Native);
   Reject(delegate { FixedFixtureImage.CreateForRecording(forgedNative,forgedNative.Domain); },"recording factory cannot install native token");
   Check(Object.ReferenceEquals(FixedImageNativeCalls.Instance.Domain,FixedImageCallDomain.Native),"native singleton domain");
   Reject(delegate { new FixedFixtureImage.CompositionLease(fresh,new object()); },"cannot mint lease without private owner key");
   ExactTrace(calls);ExactTrace(forgedNative);
   var lease=fresh.ClaimForComposition();
   Reject(delegate { fresh.ClaimForComposition(); },"claimed context rejected without altering winner");
   ExactTrace(calls);lease.PrepareOnce();Check(lease.Ready,"winning lease still usable after losing claim");
   Reject(delegate { fresh.ClaimForComposition(); },"prepared claimed context never reclaims");
   Check(lease.TryRelease(),"winning lease release");
   int count=calls.Trace.Count;
   Reject(delegate { fresh.ClaimForComposition(); },"completed claim cannot transfer back");
   Check(calls.Trace.Count==count,"claim rejection never enters native boundary");
   var preparedCalls=Calls(bytes);var prepared=Image(preparedCalls);prepared.PrepareOnce();count=preparedCalls.Trace.Count;
   Reject(delegate { prepared.ClaimForComposition(); },"standalone prepared context rejected");
   Check(preparedCalls.Trace.Count==count && prepared.Ready && prepared.TryRelease(),"rejected claim cannot damage standalone owner");
   Reject(delegate { prepared.ClaimForComposition(); },"standalone released context rejected");
   var probeCalls=Calls(bytes);var probeUsed=Image(probeCalls);
   Reject(delegate { probeUsed.ObserveSharing(); },"unprepared probe attempt refused");
   Reject(delegate { probeUsed.ClaimForComposition(); },"even failed standalone probe attempt consumes freshness");ExactTrace(probeCalls);
  }
  static void ConcurrentClaimHasOneWinner(byte[] bytes) {
   for(int attempt=0;attempt<8;attempt++) {
    var calls=Calls(bytes);var image=Image(calls);
    var start=new System.Threading.ManualResetEvent(false);
    var threads=new System.Threading.Thread[6];var winners=new FixedFixtureImage.CompositionLease[6];var faults=new Exception[6];
    for(int i=0;i<threads.Length;i++) {
     int slot=i;
     threads[i]=new System.Threading.Thread(delegate() {
      if(!start.WaitOne(5000)) { faults[slot]=new Exception("claim start timeout");return; }
      try { winners[slot]=image.ClaimForComposition(); } catch(InvalidOperationException) { } catch(Exception e) { faults[slot]=e; }
     });threads[i].IsBackground=true;threads[i].Start();
    }
    start.Set();int count=0;
    for(int i=0;i<threads.Length;i++) { Check(threads[i].Join(5000),"bounded concurrent claim join");Check(faults[i]==null,"no unexpected claim failure");if(winners[i]!=null)count++; }
    start.Close();Check(count==1,"exactly one irreversible concurrent claim winner");ExactTrace(calls);
    for(int i=0;i<winners.Length;i++)if(winners[i]!=null) { winners[i].PrepareOnce();Check(winners[i].Ready && winners[i].TryRelease(),"sole concurrent winner owns real preparation/release"); }
   }
   // A simultaneous standalone use and claim cannot both pass the same lock.
   for(int attempt=0;attempt<8;attempt++) {
    var calls=Calls(bytes);var image=Image(calls);int successes=0;Exception fault=null;
    var start=new System.Threading.ManualResetEvent(false);
    var claimant=new System.Threading.Thread(delegate() {
     if(!start.WaitOne(5000))return;
     try { image.ClaimForComposition();System.Threading.Interlocked.Increment(ref successes); } catch(InvalidOperationException) { } catch(Exception e) { fault=e; }
    });
    var releaser=new System.Threading.Thread(delegate() {
     if(!start.WaitOne(5000))return;
     try { Check(image.TryRelease(),"unopened standalone release");System.Threading.Interlocked.Increment(ref successes); } catch(InvalidOperationException) { } catch(Exception e) { fault=e; }
    });
    claimant.IsBackground=true;releaser.IsBackground=true;claimant.Start();releaser.Start();start.Set();
    Check(claimant.Join(5000) && releaser.Join(5000) && fault==null && successes==1,"claim and standalone use serialize");start.Close();ExactTrace(calls);
   }
  }
  static void TransferredFacadeCannotPrepareProbeOrRelease(byte[] bytes) {
   var calls=Calls(bytes);var image=Image(calls);var lease=image.ClaimForComposition();
   Check(!image.Ready && !lease.Ready && lease.Observation.OpenState=="not-entered","claim performs no native setup");
   for(int phase=0;phase<3;phase++) {
    int count=calls.Trace.Count;
    Reject(delegate { image.PrepareOnce(); },"transferred facade cannot prepare");
    Reject(delegate { image.ObserveSharing(); },"transferred facade cannot probe");
    Reject(delegate { image.TryRelease(); },"transferred facade cannot release");
    Reject(delegate { image.ClaimForComposition(); },"transferred facade cannot rebind");
    Check(calls.Trace.Count==count,"disabled facade never enters native boundary");
    if(phase==0) {
     lease.PrepareOnce();Check(lease.Ready && !image.Ready && lease.ObserveSharing(),"only lease has live readiness and probes");
     count=calls.Trace.Count;Reject(delegate { lease.PrepareOnce(); },"lease preparation one-shot");Reject(delegate { lease.ObserveSharing(); },"lease probes one-shot");Check(calls.Trace.Count==count,"lease one-shot guards precede calls");
    }
    if(phase==1) { Check(lease.TryRelease(),"lease checked close");Check(!lease.Ready && lease.Released,"lease readiness revoked after release"); }
   }
   Check(image.Observation.CloseState=="returned-success" && image.Released && lease.Observation.CloseState=="returned-success","facade and lease immutable snapshots remain readable forever");
  }
  static void ReadyRequiresLiveUnclosedKnownHandle(byte[] bytes) {
   foreach(string fault in new string[] {"","close-false","close-unavailable"}) {
    var calls=Calls(bytes);var image=Image(calls);Check(!image.Ready,"unopened never ready");image.PrepareOnce();
    var snapshot=image.Observation;Check(image.Ready,"complete matching actual observation is ready while held");
    calls.Fault=fault;calls.BeforeClose=delegate { Check(!image.Ready,"close entry immediately revokes readiness"); };
    bool returned=false,unavailable=false;try { returned=image.TryRelease(); } catch(Unavailable) { unavailable=true; }
    Check(returned==(fault=="") && unavailable==(fault=="close-unavailable"),"exact close result preserved");
    Check(!image.Ready && image.Released==(fault==""),"close FALSE/unavailable cannot retain cached readiness or prove release");
    Check(image.Observation.CloseState==(fault==""?"returned-success":fault=="close-false"?"returned-failure":"return-unknown"),"actual close ledger");
    Check(snapshot.CloseState=="not-entered","preclose snapshot immutable");
    int count=calls.Trace.Count;Check(image.TryRelease()==(fault==""),"repeated release returns disposition without retry");Check(calls.Trace.Count==count,"never close twice after known/unknown close");
    Reject(delegate { image.PrepareOnce(); },"no reopen after close attempt");Reject(delegate { image.ObserveSharing(); },"no probe after close attempt");
   }
  }
  static void UnopenedReleasePreventsLaterClaim(byte[] bytes) {
   var calls=Calls(bytes);var image=Image(calls);Check(image.TryRelease(),"unopened standalone release resolves without handle");
   Reject(delegate { image.ClaimForComposition(); },"unopened release permanently consumes freshness");ExactTrace(calls);
  }
  static string[] PreparedTrace(byte[] bytes,int limit,params string[] tail) {
   var expected=new System.Collections.Generic.List<string>(new string[] {"open","attributes","size","identity","path"});
   for(int remaining=bytes.Length;remaining>0;remaining-=Math.Min(limit,Math.Min(65536,remaining)))expected.Add("read");
   expected.Add("eof");expected.AddRange(tail);return expected.ToArray();
  }
  static void RealFileOwnerUsesOnlyInjectedCalls(byte[] verified) {
   var calls=Calls(verified);var image=Image(calls);image.PrepareOnce();
   Check(image.Ready && image.Observation.BytesHashed==verified.Length && image.Observation.EofRequestBytes==1 && image.Observation.EofReturnBytes==0,"actual partial reads/hash/positive terminal EOF");
   Check(image.Observation.ActualSha256==FixedFixtureBuildExpectation.Sha256 && image.Observation.VolumeSerial=="0000000000000000" && image.Observation.FileId=="01000000000000000200000000000000" && image.Observation.HeldPath=="C:\\fixture\\NativeCaptureFixtureChild.exe","actual immutable same-handle observations");
   Check(image.ObserveSharing(),"both exact known error32 probes");
   var write=image.WriteProbeObservation;var delete=image.DeleteProbeObservation;
   Check(write.Access==0x40000000 && delete.Access==0x10000 && write.Share==7 && delete.Share==7 && write.Disposition==3 && delete.Disposition==3 && write.OpenError==32 && delete.OpenError==32 && write.CloseState=="not-opened" && delete.CloseState=="not-opened","immutable actual probe observations");
   Check(image.TryRelease(),"actual image checked close");ExactTrace(calls,PreparedTrace(verified,calls.PartialLimit,"probe1","error","probe2","error","close"));
   foreach(string fault in new string[] {"open-false","open-unavailable"}) {
    calls=Calls(verified);calls.Fault=fault;image=Image(calls);bool unavailable=false;
    try { image.PrepareOnce(); } catch(Unavailable) { unavailable=true; }
    Check(unavailable==(fault=="open-unavailable") && !image.Ready,"open unavailable distinct from actual FALSE");
    Check(image.Observation.OpenState==(unavailable?"return-unknown":"returned-failure") && image.Observation.OpenError==(unavailable?(uint?)null:2U),"actual open state/error");
    Check(image.TryRelease()==!unavailable && image.Released==!unavailable,"unknown acquisition retained, FALSE open owns nothing");
    int count=calls.Trace.Count;Reject(delegate { image.PrepareOnce(); },"no open retry");Reject(delegate { image.ClaimForComposition(); },"failed/unavailable standalone preparation consumes freshness");Check(calls.Trace.Count==count,"no calls on claim rejection after failed preparation");
    if(unavailable)ExactTrace(calls,"open");else ExactTrace(calls,"open","error");
   }
   foreach(string operation in new string[] {"attributes","size","identity","path"})foreach(bool unavailable in new bool[] {false,true}) {
    calls=Calls(verified);calls.Fault=operation+(unavailable?"-unavailable":"-false");image=Image(calls);bool rejected=false;
    try { image.PrepareOnce(); } catch(Unavailable) { rejected=unavailable; } catch(System.IO.IOException) { rejected=!unavailable; } catch(ArgumentException) { rejected=!unavailable; }
    Check(rejected && !image.Ready,"actual metadata failure/unavailable refuses preparation");
    Check(image.TryRelease()==!unavailable && image.Released==!unavailable,"unavailable synchronous metadata retains exact owner");
    var expected=new System.Collections.Generic.List<string>();
    foreach(string name in new string[] {"open","attributes","size","identity","path"}) { expected.Add(name);if(name==operation)break; }
    if(!unavailable) { expected.Add("error");expected.Add("close"); }
    ExactTrace(calls,expected.ToArray());int count=calls.Trace.Count;
    Reject(delegate { image.PrepareOnce(); },"no metadata retry");Check(image.TryRelease()==!unavailable && calls.Trace.Count==count,"no second metadata/close boundary");
   }
   foreach(string fault in new string[] {"read-false","read-unavailable","eof-false","eof-unavailable","early","oversize","extra"}) {
    calls=Calls(verified);calls.Fault=fault;image=Image(calls);bool unavailable=false;
    try { image.PrepareOnce(); } catch(Unavailable) { unavailable=true; }
    Check(unavailable==fault.EndsWith("unavailable",StringComparison.Ordinal) && !image.Ready,"real read failure refuses readiness");
    var o=image.Observation;
    Check(o.ActualSha256==null && o.ReadState==(unavailable?"return-unknown":fault.EndsWith("false",StringComparison.Ordinal)?"returned-failure":"known-incomplete"),"no partial digest or fabricated read return");
    Check(o.ReadError==(fault.EndsWith("false",StringComparison.Ordinal)?5U:(uint?)null),"immediate known read error only");
    if(fault=="early")Check(o.BytesHashed==0 && o.EofRequestBytes==Math.Min(65536,verified.Length) && o.EofReturnBytes==0,"actual premature EOF counts");
    if(fault=="oversize")Check(o.BytesHashed==0 && o.EofRequestBytes==null,"impossible count is never hashed");
    if(fault=="extra")Check(o.BytesHashed==verified.Length && o.EofRequestBytes==1 && o.EofReturnBytes==1,"extra terminal byte never hashed");
    Check(image.TryRelease()==!unavailable,"unknown read forbids close; known read failure permits checked close");
    var expected=new System.Collections.Generic.List<string>(new string[] {"open","attributes","size","identity","path"});
    if(fault.StartsWith("eof",StringComparison.Ordinal) || fault=="extra") {
     string[] prepared=PreparedTrace(verified,calls.PartialLimit);expected.Clear();expected.AddRange(prepared);
    } else expected.Add("read");
    if(fault.EndsWith("false",StringComparison.Ordinal))expected.Add("error");
    if(!unavailable)expected.Add("close");ExactTrace(calls,expected.ToArray());
    int count=calls.Trace.Count;Reject(delegate { image.PrepareOnce(); },"no read retry");Check(image.TryRelease()==!unavailable && calls.Trace.Count==count,"never close unresolved read or retry release");
   }
   foreach(long size in new long[] {0,FixedImageState.MaxImage+1,verified.Length+1}) {
    calls=Calls(verified);calls.Size=size;image=Image(calls);image.PrepareOnce();
    Check(!image.Ready && image.Observation.Refusal=="size-mismatch" && image.Observation.ActualSize==size && image.Observation.ReadState=="not-entered" && image.TryRelease(),"size refusal precedes identity/path/hash");ExactTrace(calls,"open","attributes","size","close");
   }
   byte[] changed=(byte[])verified.Clone();changed[0]^=1;calls=Calls(changed);image=Image(calls);image.PrepareOnce();
   Check(!image.Ready && image.Observation.Refusal=="digest-mismatch" && image.Observation.ReadState=="complete" && image.Observation.ActualSha256==Digest(changed) && image.Expected.Sha256==FixedFixtureBuildExpectation.Sha256 && image.TryRelease(),"negative changes verified cloned bytes, never embedded expectations");
   foreach(string fault in new string[] {"probe1-unavailable","probe-error","probe-success","probe-close-false","probe-close-unavailable"}) {
    calls=Calls(verified);calls.Fault=fault;image=Image(calls);image.PrepareOnce();bool unavailable=false,denied=false;
    try { denied=image.ObserveSharing(); } catch(Unavailable) { unavailable=true; }
    bool retained=fault=="probe1-unavailable" || fault=="probe-close-false" || fault=="probe-close-unavailable";
    Check(!denied && unavailable==(fault=="probe1-unavailable" || fault=="probe-close-unavailable"),"exact probe false/unavailable/success outcomes");
    Check(!retained || !image.Ready,"probe uncertainty revokes readiness");
    var old=image.WriteProbeObservation;Check(old!=null,"actual attempted probe snapshot");
    if(retained)Check(image.DeleteProbeObservation==null,"unresolved first probe stops second");
    Check(image.TryRelease()==!retained && image.Released==!retained,"unresolved probe retains entire image");
    var tail=new System.Collections.Generic.List<string>();tail.Add("probe1");
    if(fault!="probe1-unavailable") {
     if(fault=="probe-error") { tail.Add("error");tail.Add("probe2");tail.Add("error"); }
     else { tail.Add("probe-close");if(fault=="probe-close-false")tail.Add("error");if(fault=="probe-success") { tail.Add("probe2");tail.Add("probe-close"); } }
    }
    if(!retained)tail.Add("close");ExactTrace(calls,PreparedTrace(verified,calls.PartialLimit,tail.ToArray()));
    int count=calls.Trace.Count;Reject(delegate { image.ObserveSharing(); },"probe one-shot even after unavailable result");Check(image.TryRelease()==!retained && calls.Trace.Count==count,"never retry probe close or release retained image");
    Check(old.OpenState==image.WriteProbeObservation.OpenState && old.CloseState==image.WriteProbeObservation.CloseState,"probe snapshot immutable");
   }
  }
  public static int RunInjectedOwners(byte[] pristineBytes) {
   byte[] verified=VerifiedPristine(pristineBytes);
   Reject(delegate { VerifiedPristine(null); },"null pristine bytes");
   Reject(delegate { VerifiedPristine(new byte[0]); },"empty pristine bytes");
   byte[] wrong=(byte[])verified.Clone();wrong[0]^=1;
   Reject(delegate { VerifiedPristine(wrong); },"same-size altered pristine bytes rejected before fake setup");
   byte[] copy=VerifiedPristine(verified);copy[0]^=1;Check(Digest(verified)==FixedFixtureBuildExpectation.Sha256,"verified input cloned before use");
   ClaimRejectsPreparedReleasedAndReused(verified);
   ConcurrentClaimHasOneWinner(verified);
   TransferredFacadeCannotPrepareProbeOrRelease(verified);
   ReadyRequiresLiveUnclosedKnownHandle(verified);
   UnopenedReleasePreventsLaterClaim(verified);
   RealFileOwnerUsesOnlyInjectedCalls(verified);
   Console.WriteLine("PASS fixed image injected owners");return 0;
  }
  public static int RunManaged() {
   var expected=new FixedImageExpectation(1,new string('a',64));
   Check(expected.Length==1 && expected.Sha256==new string('a',64),"exact expectation");
   foreach(long bad in new long[] {0,-1,16777217})Reject(delegate { new FixedImageExpectation(bad,new string('a',64)); },"expectation length bound");
   foreach(string bad in new string[] {null,"",new string('a',63),new string('A',64),new string('g',64),new string('a',64)+"\n"})Reject(delegate { new FixedImageExpectation(1,bad); },"exact digest syntax");
   string source=FixedImageExpectation.Source(17,new string('b',64));
   Check(FixedImageExpectation.ParseSource(source).Length==17,"fixed source parsing");
   foreach(string bad in new string[] {source+" ",source.Replace("17L","017L"),source.Replace("NativeCaptureFixtureChild.exe","other.exe"),source.Replace("17L","0L"),new string('x',2049)})Reject(delegate { FixedImageExpectation.ParseSource(bad); },"fixed syntax/source bound");
   Check(FixedImageExpectation.Source(16777216,new string('a',64)).Length<=2048,"generated source bounded");
   var preparation=new FixedImageState(expected);preparation.BeginPreparation();Reject(delegate { preparation.BeginPreparation(); },"single-use preparation before native entry");
   var unopened=new FixedImageState(expected);Check(unopened.CloseState=="not-opened" && unopened.ReadState=="not-entered","initial unavailable observations");
   unopened.EnterOpen();Reject(delegate { unopened.EnterOpen(); },"unknown open cannot retry");Check(!unopened.CanRelease,"unknown open retained");
   var failed=new FixedImageState(expected);failed.EnterOpen();failed.ReturnOpen(false,2);Check(failed.OpenError==2 && failed.CloseState=="not-opened","known open failure");Reject(delegate { failed.EnterOpen(); },"failed open one-shot");
   var unknown=Open(17);unknown.EnterRead(17);Check(!unknown.CanRelease,"unknown read retained");Reject(delegate { unknown.EnterRead(1); },"unknown read no reuse");Reject(delegate { unknown.EnterClose(); },"unknown read no close");
   foreach(int request in new int[] {0,65537,-1}) { var s=Open(17);Reject(delegate { s.EnterRead(request); },"positive 64 KiB request bound"); }
   var partial=Open(17);Read(partial,17,3);Read(partial,14,14);Read(partial,1,0);partial.CompleteHash(new string('b',64));Check(partial.ReadState=="complete" && partial.BytesHashed==17 && partial.EofRequestBytes==1 && partial.EofReturnBytes==0,"partial reads and positive EOF");
   var snapshot=partial.Snapshot();partial.EnterClose();partial.ReturnClose(true);Check(snapshot.CloseState=="not-entered" && partial.Snapshot().CloseState=="returned-success","immutable snapshot");Reject(delegate { partial.EnterClose(); },"successful close no retry");
   var exact=Open(16777216);for(int i=0;i<256;i++)Read(exact,65536,65536);Check(exact.BytesHashed==16777216,"exact 16 MiB consumed");Read(exact,1,0);exact.CompleteHash(new string('a',64));Check(exact.ReadState=="complete","positive terminal request at exact 16 MiB");
   var noEof=Open(17);Read(noEof,17,17);Reject(delegate { noEof.CompleteHash(new string('a',64)); },"no digest without terminal request");Reject(delegate { noEof.EnterRead(0); },"zero-length EOF proof rejected");
   var pending=Open(17);pending.EnterRead(17);pending.ReturnRead(true,3,null);Reject(delegate { pending.EnterRead(14); },"cannot read before accepted hash accounting");pending.HashFailed();Check(pending.BytesHashed==0 && pending.ReadState=="known-incomplete","transform failure does not count unaccepted bytes");
   var overflow=Open(17);overflow.EnterRead(17);overflow.ReturnRead(true,18,null);Check(overflow.ReadState=="known-incomplete" && overflow.BytesHashed==0,"impossible count rejects");
   var early=Open(17);Read(early,17,0);Check(early.ReadState=="known-incomplete" && early.EofRequestBytes==17 && early.EofReturnBytes==0 && early.ActualSha256==null,"premature EOF preserved");Reject(delegate { early.CompleteHash(new string('a',64)); },"no partial digest");
   var extra=Open(17);Read(extra,17,17);Read(extra,1,1);Check(extra.ReadState=="known-incomplete" && extra.BytesHashed==17 && extra.EofReturnBytes==1 && extra.ActualSha256==null,"extra byte never hashed");
   var hashFault=Open(17);Read(hashFault,17,17);Read(hashFault,1,0);hashFault.HashFailed();Check(hashFault.ReadState=="known-incomplete" && hashFault.ReadError==null && hashFault.ActualSha256==null && hashFault.EofReturnBytes==0,"managed hash failure not native read error");
   var badReturns=Open(17);Reject(delegate { badReturns.ReturnRead(true,0,null); },"read return requires entry");Reject(delegate { badReturns.ReturnClose(true); },"close return requires entry");
   var failedEntry=new FixedImageState(expected);Reject(delegate { failedEntry.ReturnOpen(false,2); },"open return requires entry");failedEntry.EnterOpen();Reject(delegate { failedEntry.ReturnOpen(true,2); },"successful open cannot invent error");Check(failedEntry.OpenState=="return-unknown","inconsistent return remains unresolved");
   var readFailure=Open(17);readFailure.EnterRead(17);readFailure.ReturnRead(false,0,5);Check(readFailure.ReadState=="returned-failure" && readFailure.ReadError==5 && readFailure.CanRelease,"known native read failure releasable");
   foreach(bool success in new bool[] {false,true}) { var s=Open(17);s.EnterClose();Check(!s.CanRelease && s.CloseState=="return-unknown","close entry irreversible");s.ReturnClose(success);Reject(delegate { s.EnterClose(); },"known close never retries");Check(s.Released==success,"checked close success only"); }
   var closeUnknown=Open(17);closeUnknown.EnterClose();Reject(delegate { closeUnknown.EnterClose(); },"unknown close no retry");
   foreach(uint attributes in new uint[] {0x10,0x400,0x410})Reject(delegate { FixedImageCodec.Leaf(attributes); },"directory/reparse leaf refused");FixedImageCodec.Leaf(0x80);
   Check(NativeFixedImageIdentityNativeTests.Main(new string[] {"matching-image"})==3,"arguments rejected before native entry");
   var metadata=Open(17);Reject(delegate { metadata.ObserveIdentity(false,0,0,0); },"unsupported identity fails");Check(metadata.Snapshot().VolumeSerial==null,"unsupported identity unavailable");
   metadata.ObserveIdentity(true,0,1,2);Check(metadata.Snapshot().VolumeSerial=="0000000000000000" && metadata.Snapshot().FileId=="01000000000000000200000000000000","actual zero serial allowed");
   foreach(string path in new string[] {null,"","\\\\server\\share\\file","\\\\?\\UNC\\server\\file","C:relative","C:\\bad\0path","C:\\bad\ud800","C:\\bad\udc00"})Reject(delegate { FixedImageCodec.LocalPath(path); },"malformed/non-DOS path");
   Check(FixedImageCodec.LocalPath("C:\\file")=="C:\\file" && FixedImageCodec.LocalPath("\\\\?\\C:\\file")=="\\\\?\\C:\\file","raw local DOS path retained");
   Reject(delegate { FixedImageCodec.FinalPath("C:\\x",32768); },"truncated native path return");Reject(delegate { FixedImageCodec.FinalPath("C:\\x",0); },"failed native path return");Reject(delegate { FixedImageCodec.FinalPath("C:\\x",3); },"native path count mismatch");
   Check(FixedImageCodec.FinalPath("C:\\x",4)=="C:\\x","exact native path count");
   foreach(uint access in new uint[] {0x40000000,0x10000}) { var call=new FixedImageProbeCall(access,7,3);Check(call.Access==access && call.Share==7 && call.Disposition==3,"native-consumed immutable probe request"); }
   FixedImageProbe.ValidateCall(0x40000000,7,3);FixedImageProbe.ValidateCall(0x10000,7,3);
   foreach(uint share in new uint[] {0,1,3,5,6,8})Reject(delegate { new FixedImageProbeCall(0x40000000,share,3); },"incompatible sharing is false assurance");
   Reject(delegate { FixedImageProbe.ValidateCall(0x80000000,7,3); },"probe exact access");Reject(delegate { FixedImageProbe.ValidateCall(0x10000,7,2); },"probe exact disposition");
   var owner=FixedFixtureImage.CreateForObservation();Check(owner.Observation.OpenState=="not-entered","sealed owner initially unopened");
   Check(typeof(FixedFixtureImage).GetConstructors().Length==0,"no public native constructor");
   byte[] data=Encoding.ASCII.GetBytes("fixed managed bytes");Check(Digest(data).Length==64,"managed hashing available");
   PathContracts();
   ProbeContracts();
   for(int mode=0;mode<3;mode++)Console.WriteLine("PROBE_DIAGNOSTIC "+ProbeFaultReport(mode));
   string unicode=UnicodeReport();
   foreach(char c in unicode)Check(c<=127,"ASCII-only JSON preserves actual Unicode path across console encodings");
   Console.WriteLine("SERIALIZER_UNICODE "+unicode);
   Console.WriteLine("PASS fixed image managed contracts");return 0;
  }
 }
}
