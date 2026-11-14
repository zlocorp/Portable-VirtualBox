// TEST ONLY. Closed recording domain, genuine child bytes and actual owner decisions.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
namespace PortableVBox {
 internal sealed class FixedImageCompositionTestRig {
  internal sealed class Unavailable : Exception { }
  internal readonly FixedImageCallDomain Domain=FixedImageCallDomain.CreateRecording();
  internal readonly List<string> Trace=new List<string>();
  internal readonly FixedFixtureImage Image;
  internal readonly FixedImageCompositionBindings Bindings;
  internal readonly FileCalls File;
  internal readonly ProcessCalls Process;
  internal readonly RecordingFlow Flow;
  internal readonly FreshCalls Sentinel;
  internal string Fault="";
  internal bool StdoutEof=true,StderrEof=true;
  internal uint Wait=0,Code=0;
  internal string ProcessPath=@"\\?\c:\fixture\NativeCaptureFixtureChild.exe";
  internal FixedImageCompositionTestRig(byte[] pristineBytes) {
   if(pristineBytes==null)throw new ArgumentException("Genuine pristine bytes required");
   byte[] copy=(byte[])pristineBytes.Clone();
   using(var sha=SHA256.Create())if(copy.LongLength!=FixedFixtureBuildExpectation.Length || FixedImageCodec.Hex(sha.ComputeHash(copy))!=FixedFixtureBuildExpectation.Sha256)throw new ArgumentException("Genuine pristine bytes required");
   File=new FileCalls(this,copy);Process=new ProcessCalls(this);Flow=new RecordingFlow(this);Sentinel=new FreshCalls(this);
   Image=FixedFixtureImage.CreateForRecording(File,Domain);
   Bindings=FixedImageCompositionBindings.CreateRecording(Image,Process,Flow,Sentinel);
  }
  internal ChildCaptureOwner CreateOwner() { return new ChildCaptureOwner(Image,Bindings); }
  internal void Enter(string name) { Trace.Add(name);if(Fault==name+"-unavailable")throw new Unavailable(); }
  internal static void Check(bool value,string label) { if(!value)throw new Exception("ASSERT "+label); }
  internal sealed class FileCalls : IFixedImageNativeCalls {
   readonly FixedImageCompositionTestRig rig;readonly byte[] bytes;int position;uint? error;
   internal FileCalls(FixedImageCompositionTestRig rig,byte[] bytes) { this.rig=rig;this.bytes=bytes; }
   public FixedImageCallDomain Domain { get { return rig.Domain; } }
   void Enter(string name) { Check(!error.HasValue,"immediate file last-error capture");rig.Enter(name); }
   public uint CaptureLastError() { Check(error.HasValue,"known file error only");uint result=error.Value;error=null;rig.Trace.Add("file-error");return result; }
   public IntPtr CreateFileW(string name,uint access,uint share,IntPtr security,uint disposition,uint flags,IntPtr template) {
    string expected=Path.Combine(Path.GetDirectoryName(typeof(FixedImageCompositionTestRig).Assembly.Location),"NativeCaptureFixtureChild.exe");
    Check(name==expected && security==IntPtr.Zero && disposition==3 && template==IntPtr.Zero,"fixed sibling non-inheritable OPEN_EXISTING");
    if(access==0x80000000) {
     Check(share==1 && flags==0x00200000,"held image read-only share-read reparse refusal");Enter("image-open");
     if(rig.Fault=="missing") { error=2;return new IntPtr(-1); }return new IntPtr(201);
    }
    Check((access==0x40000000 || access==0x10000) && share==7 && flags==0,"exact sharing probes");
    Enter(access==0x40000000?"probe-write":"probe-delete");
    if(rig.Fault=="probe-success" || rig.Fault.StartsWith("probe-close-",StringComparison.Ordinal))return new IntPtr(301);
    error=rig.Fault=="probe-error"?5U:32U;return new IntPtr(-1);
   }
   void Held(IntPtr value) { Check(value==new IntPtr(201),"exact held image handle"); }
   public bool Attributes(IntPtr handle,int info,out FixedImageNative.AttributeTag value,uint size) {
    Held(handle);Check(info==9 && size==8,"exact attributes query");Enter("attributes");value=new FixedImageNative.AttributeTag();value.Attributes=0x80;return true;
   }
   public bool GetFileSizeEx(IntPtr handle,out long size) { Held(handle);Enter("size");size=bytes.Length+(rig.Fault=="size"?1:0);return true; }
   public bool Identity(IntPtr handle,int info,out FixedImageNative.IdInfo value,uint size) {
    Held(handle);Check(info==18 && size==24,"exact file ID");Enter("identity");value=new FixedImageNative.IdInfo();value.Low=1;return true;
   }
   public uint GetFinalPathNameByHandleW(IntPtr handle,StringBuilder buffer,uint length,uint flags) {
    Held(handle);Check(buffer.Capacity==32768 && length==32768 && flags==0,"held query bound");Enter("held-path");buffer.Append(@"C:\fixture\NativeCaptureFixtureChild.exe");return (uint)buffer.Length;
   }
   public bool ReadFile(IntPtr handle,byte[] target,uint request,out uint read,IntPtr overlapped) {
    Held(handle);Check(request>0 && request<=65536 && overlapped==IntPtr.Zero,"positive synchronous image reads");Enter(position==bytes.Length?"image-eof":"image-read");
    if(rig.Fault=="image-read-false") { read=0;error=5;return false; }
    if(position==bytes.Length) { Check(request==1,"positive image EOF request");read=0;return true; }
    read=(uint)Math.Min((int)request,bytes.Length-position);Array.Copy(bytes,position,target,0,(int)read);
    if(rig.Fault=="digest" && position==0)target[0]^=1;
    position+=(int)read;return true;
   }
   public bool CloseHandle(IntPtr handle) {
    Check(handle==new IntPtr(201) || handle==new IntPtr(301),"only file-domain handles close");string name=handle==new IntPtr(201)?"image-close":"probe-close";Enter(name);
    if(rig.Fault==name+"-false") { error=6;return false; }return true;
   }
  }
  internal sealed class ProcessCalls : IChildCaptureProcessCalls {
   readonly FixedImageCompositionTestRig rig;uint? error;
   internal string Command,Application,Directory;
    internal ProcessCalls(FixedImageCompositionTestRig rig) { this.rig=rig; }
   public FixedImageCallDomain Domain { get { return rig.Domain; } }
   void Enter(string name) { Check(!error.HasValue,"immediate process error capture");rig.Enter(name); }
   public uint CaptureLastError() { Check(error.HasValue,"known process error only");uint result=error.Value;error=null;rig.Trace.Add("process-error");return result; }
   public bool CreateProcessW(string image,StringBuilder command,IntPtr processSecurity,IntPtr threadSecurity,bool inherit,uint flags,IntPtr environment,string directory,ref ChildCaptureApi.ExtendedStartup startup,out ChildCaptureApi.ProcessInfo information) {
    Check(processSecurity==IntPtr.Zero && threadSecurity==IntPtr.Zero && inherit && flags==0x80000U && environment==IntPtr.Zero,"unchanged CreateProcess flags and inherited allowlist startup");
    Check(startup.Startup.Size==112 && startup.Startup.Flags==0x100 && startup.Startup.Input==IntPtr.Zero && startup.Startup.Output==IntPtr.Zero && startup.Startup.Error==IntPtr.Zero && startup.Attributes==IntPtr.Zero,"recording never allocates synthetic transport/attribute handles");
    Check(rig.Image.Observation.ReadState=="complete" && rig.Image.Observation.ActualSha256==FixedFixtureBuildExpectation.Sha256 && rig.Image.WriteProbeObservation.OpenError==32 && rig.Image.DeleteProbeObservation.OpenError==32,"hash and both real sharing observations before create");
    Application=image;Command=command.ToString();Directory=directory;
    Enter("create");information=new ChildCaptureApi.ProcessInfo();
    if(rig.Fault=="create-false") { error=2;return false; }
    information.Process=rig.Fault=="process-zero"?IntPtr.Zero:rig.Fault=="process-invalid"?new IntPtr(-1):new IntPtr(401);
    information.Thread=rig.Fault=="thread-zero"?IntPtr.Zero:rig.Fault=="thread-invalid"?new IntPtr(-1):new IntPtr(402);
    information.Pid=777;information.Tid=778;return true;
   }
   public bool QueryFullProcessImageNameW(IntPtr handle,uint flags,StringBuilder buffer,ref uint capacity) {
    Check(handle==new IntPtr(401) && flags==0 && capacity==32768 && buffer.Capacity==32768,"query exact Original.Process once, flags zero, WCHAR capacity 32768");Enter("query");
    if(rig.Fault=="query-false") { error=5;return false; }
    buffer.Append(rig.ProcessPath);capacity=rig.Fault=="query-truncated"?32768U:rig.Fault=="query-count"?1U:(uint)buffer.Length;return true;
   }
   public uint WaitForSingleObject(IntPtr handle,uint milliseconds) {
    Check(milliseconds==0 && (handle==new IntPtr(401) || handle==new IntPtr(501)),"exact original process or sentinel wait only");
    if(handle==new IntPtr(501)) { Enter("sentinel-wait");return 258; }
    Enter("wait");if(rig.Wait==0xffffffff)error=6;return rig.Wait;
   }
   public bool GetExitCodeProcess(IntPtr handle,out uint code) {
    Check(handle==new IntPtr(401),"exit query exact Original.Process");Enter("exit-code");code=rig.Code;
    if(rig.Fault=="exit-code-false") { error=6;return false; }return true;
   }
   public bool CloseHandle(IntPtr handle) {
    Check(handle==new IntPtr(401) || handle==new IntPtr(402),"no process close via PipeNative or substitute");string name=handle==new IntPtr(401)?"process-close":"thread-close";Enter(name);
    if(rig.Fault==name+"-false") { error=6;return false; }return true;
   }
  }
  internal sealed class FreshCalls : IChildCaptureRecordingSentinelCalls {
   readonly FixedImageCompositionTestRig rig;
   internal FreshCalls(FixedImageCompositionTestRig rig) { this.rig=rig; }
   public FixedImageCallDomain Domain { get { return rig.Domain; } }
   public void ClearLastError() { rig.Trace.Add("sentinel-clear"); }
   public uint CaptureLastError() { rig.Trace.Add("sentinel-error");return 0; }
   public IntPtr CreateEvent(IntPtr descriptor,bool manualReset,bool initialState,bool inherit,string name) {
    Check(descriptor==IntPtr.Zero && manualReset && !initialState && !inherit && name.StartsWith("Local\\pvbox-fixed-sentinel-",StringComparison.Ordinal),"actual fresh sentinel contract");rig.Enter("sentinel-create");return new IntPtr(501);
   }
   public bool SetHandleInformation(IntPtr handle,uint mask,uint flags) { Check(handle==new IntPtr(501) && mask==1 && flags==1,"actual sentinel inheritance");rig.Enter("sentinel-flags");return true; }
   public bool CloseHandle(IntPtr handle) { Check(handle==new IntPtr(501),"sentinel closes only through its domain adapter");rig.Enter("sentinel-close");return true; }
  }
  internal sealed class RecordingFlow : IChildCaptureFlow {
   readonly FixedImageCompositionTestRig rig;
   internal RecordingFlow(FixedImageCompositionTestRig rig) { this.rig=rig; }
   public FixedImageCallDomain Domain { get { return rig.Domain; } }
   public void PrepareTransport(ChildCaptureOwner owner) { rig.Enter("transport");owner.PrepareFreshSentinel(IntPtr.Zero);AssertEmptyTransport(owner); }
   public void CloseParentWriters(ChildCaptureOwner owner) { rig.Enter("writers");owner.CloseParentWriters(); }
   public void Pump(ChildCaptureOwner owner) {
    rig.Enter("pump");AssertEmptyTransport(owner);
    byte[] header={80,86,67,50,1,0,0,165};owner.Channels[0].Capture.Receive(header,header.Length);
    byte[] data=new byte[4097];for(int i=0;i<data.Length;i++)data[i]=(byte)((i*31)&255);owner.Channels[0].Capture.Receive(data,4096);owner.Channels[0].Capture.Receive(new byte[] {data[4096]},1);
    byte[] stderr=new byte[257];for(int i=0;i<stderr.Length;i++)stderr[i]=(byte)((i*31+71)&255);owner.Channels[1].Capture.Receive(stderr,stderr.Length);
    if(rig.StdoutEof)owner.Channels[0].Capture.ObserveTerminalError(109);
    if(rig.StderrEof)owner.Channels[1].Capture.ObserveTerminalError(109);
    owner.ObserveExit();
    // Model the real bounded pump deadline, not a new native wait or cleanup path.
    if(!owner.Proof.ExitObserved || !rig.StdoutEof || !rig.StderrEof)owner.Proof.Fault();
   }
   public void InspectSentinel(ChildCaptureOwner owner) { rig.Enter("sentinel");owner.InspectSentinel(); }
   public void Recover(ChildCaptureOwner owner) { rig.Enter("recover");AssertEmptyTransport(owner);owner.Recover(); }
   internal static void AssertEmptyTransport(ChildCaptureOwner owner) {
    foreach(var c in owner.Channels) {
     Check(c.Server==IntPtr.Zero && c.Writer==IntPtr.Zero,"no real transport handle");
     foreach(var slot in new PipeNativeSlot[] {c.Connect,c.Read})Check(slot.Handle==IntPtr.Zero && slot.Buffer==IntPtr.Zero && slot.Overlapped==IntPtr.Zero && slot.Event==IntPtr.Zero,"no synthetic slot/allocation handles");
    }
   }
  }
 }
 public static class NativeFixedImageCompositionTests {
  static void Check(bool value,string label) { FixedImageCompositionTestRig.Check(value,label); }
  static void Reject(Action action,string label) { bool rejected=false;try { action(); } catch(ArgumentException) { rejected=true; } catch(InvalidOperationException) { rejected=true; }Check(rejected,label); }
  static int Count(FixedImageCompositionTestRig rig,string call) { return rig.Trace.FindAll(delegate(string item) { return item==call; }).Count; }
  static void NoCreate(ChildCaptureOwner owner,FixedImageCompositionTestRig rig) {
   Check(owner.CreateCalls==0 && owner.CreateState==CreateEntryState.NotEntered && !owner.Created && !owner.ProcessImageObservation.Entered && owner.ProcessImageObservation.ReturnedLength==null,"preflight refusal before actual create/query ledgers");
   Check(Count(rig,"transport")==0 && Count(rig,"create")==0 && Count(rig,"query")==0 && Count(rig,"pump")==0,"preflight refusal before all transport/create/query/pump boundaries");
   // A real BeforeCreate entry would make CanRelease false without a create return.
   Check(owner.Proof.CanRelease && !owner.Proof.ExitObserved && !owner.Proof.StdoutEof && !owner.Proof.StderrEof,"no invented create/EOF/exit for refusal");
  }
  static void RealConstructorClaimsOnce(byte[] bytes) {
   Check(Object.ReferenceEquals(FixedImageCompositionBindings.Native.Domain,FixedImageCallDomain.Native) && Object.ReferenceEquals(FixedImageCompositionBindings.Native.Process,ChildCaptureProcessCalls.Instance) && Object.ReferenceEquals(FixedImageCompositionBindings.Native.Flow,ChildCaptureFlow.Instance) && FixedImageCompositionBindings.Native.Sentinel is SentinelNativeCalls,"native default bundle contains actual native adapters only");
   var native=FixedFixtureImage.CreateForObservation();new ChildCaptureOwner(native);
   Reject(delegate { new ChildCaptureOwner(native); },"native constructor claims once without entering a native adapter");
   var rig=new FixedImageCompositionTestRig(bytes);var owner=rig.CreateOwner();
   Check(rig.Trace.Count==0 && owner.Scenario==CaptureCase.Binary && !owner.ProcessImageObservation.Entered && owner.ProcessImageObservation.ReturnedLength==null,"constructor has no native calls and selects only Binary");
   Reject(delegate { rig.CreateOwner(); },"same real constructor claim cannot repeat");
   Reject(delegate { rig.Image.PrepareOnce(); },"transferred facade cannot prepare");Reject(delegate { rig.Image.ObserveSharing(); },"transferred facade cannot probe");Reject(delegate { rig.Image.TryRelease(); },"transferred facade cannot close");
   owner.Run();Check(owner.Released && !owner.Unknown,"sole owner survives losing claim");Reject(delegate { rig.CreateOwner(); },"released image never transfers back");
   Reject(delegate { rig.Image.TryRelease(); },"facade remains read-only after release");
   foreach(string used in new string[] {"prepare","release","probe"}) {
    rig=new FixedImageCompositionTestRig(bytes);
    if(used=="prepare")rig.Image.PrepareOnce();else if(used=="release")rig.Image.TryRelease();else Reject(delegate { rig.Image.ObserveSharing(); },"unprepared probe rejected");
    int calls=rig.Trace.Count;Reject(delegate { rig.CreateOwner(); },"standalone use precludes composition");Check(rig.Trace.Count==calls,"claim rejection no setup");
   }
  }
  static void RealRunRefusesBeforeTransportOrCreate(byte[] bytes) {
   foreach(string fault in new string[] {"missing","size","digest","probe-error","probe-success","probe-write-unavailable","probe-delete-unavailable","probe-close-false","probe-close-unavailable","image-open-unavailable","image-read-unavailable"}) {
    var rig=new FixedImageCompositionTestRig(bytes);rig.Fault=fault;var owner=rig.CreateOwner();owner.Run();NoCreate(owner,rig);
    bool retain=fault.EndsWith("unavailable",StringComparison.Ordinal) || fault=="probe-close-false";
    Check(owner.Released==!retain && rig.Image.Released==!retain && owner.Unknown,"preflight known refusal released, unresolved acquisition retained: "+fault);
    Check(Count(rig,"image-close")==(!retain && fault!="missing"?1:0),"preflight exact image close only when resolved: "+fault);
    if(fault=="digest")Check(rig.Image.Observation.ActualSize==bytes.Length && rig.Image.Observation.ReadState=="complete" && rig.Image.Observation.Refusal=="digest-mismatch","same-length change reaches hash comparison");
    if(fault=="size")Check(Count(rig,"image-read")==0,"size mismatch before hashing");
    int count=rig.Trace.Count;Reject(delegate { owner.Run(); },"preflight use one-shot");owner.Release();Check(rig.Trace.Count==count,"preflight no retries");
   }
  }
  static void RealRunIsOneShot(byte[] bytes) {
   var rig=new FixedImageCompositionTestRig(bytes);var owner=rig.CreateOwner();
   Reject(delegate { owner.CompositionSnapshot("matching-image",false); },"snapshot requires Run");
   owner.Run();int count=rig.Trace.Count;
   Reject(delegate { owner.CompositionSnapshot("matching-image",false); },"snapshot requires one-shot assertion");
   Reject(delegate { owner.Run(); },"real Run refuses repeated use before all effects");owner.Release();Check(rig.Trace.Count==count && owner.Released,"no repeated create/close/release");
  }
  static void SharedCommandFormatterPreservesLegacyBytes(byte[] bytes) {
   CultureInfo old=System.Threading.Thread.CurrentThread.CurrentCulture;
   try {
    System.Threading.Thread.CurrentThread.CurrentCulture=new CultureInfo("ar-SA");
    foreach(string mode in Enum.GetNames(typeof(CaptureCase)))foreach(string path in new string[] {@"C:\fixed\NativeCaptureFixtureChild.exe",@"C:\a b\NativeCaptureFixtureChild.exe","C:\\a\"b\\NativeCaptureFixtureChild.exe"}) {
     string token="0123456789abcdef0123456789abcdef";
     foreach(long candidate in new long[] {1,501,Int64.MaxValue}) {
      string expected="\""+path+"\" "+mode+" "+candidate.ToString(CultureInfo.InvariantCulture)+" "+token;
      Check(FixedFixtureCommand.Format(path,mode,candidate,token).ToString()==expected,"shared formatter preserves original inline bytes for every old scenario/path/candidate/token");
     }
    }
   } finally { System.Threading.Thread.CurrentThread.CurrentCulture=old; }
   var rig=new FixedImageCompositionTestRig(bytes);var lease=rig.Image.ClaimForComposition();
   Reject(delegate { lease.BindBinaryLaunch(501,new string('a',32)); },"cannot bind unprepared image");lease.PrepareOnce();
   Reject(delegate { lease.BindBinaryLaunch(501,new string('a',32)); },"cannot bind before both exact probes");Check(lease.ObserveSharing(),"both probes before binding");
   foreach(long value in new long[] {0,-1,Int64.MinValue})Reject(delegate { lease.BindBinaryLaunch(value,new string('a',32)); },"invalid fixed Binary candidate");
   foreach(string value in new string[] {null,"",new string('A',32),new string('a',31),new string('a',33),new string('a',31)+"\n"})Reject(delegate { lease.BindBinaryLaunch(501,value); },"invalid fixed Binary token");
   var binding=lease.BindBinaryLaunch(501,new string('a',32));string root=Path.GetDirectoryName(typeof(NativeFixedImageCompositionTests).Assembly.Location);
   Check(binding.Application==Path.Combine(root,"NativeCaptureFixtureChild.exe") && binding.Directory==root && binding.Command.ToString()=="\""+binding.Application+"\" Binary 501 "+new string('a',32),"sealed fixed sibling Binary binding");
   binding.Command.Append(" changed");Check(!binding.Command.ToString().EndsWith(" changed",StringComparison.Ordinal),"binding command immutable");
   Check(lease.TryRelease(),"test capability checked release");Reject(delegate { lease.BindBinaryLaunch(501,new string('a',32)); },"no binding after image close");
  }
  static void RealLaunchUsesFixedBindingAndOriginalHandles(byte[] bytes) {
   var rig=new FixedImageCompositionTestRig(bytes);var owner=rig.CreateOwner();owner.Run();
   Check(owner.Released && owner.Proof.Complete && !owner.Unknown && owner.CreateCalls==1 && owner.CreateState==CreateEntryState.ReturnedTrue,"known-success actual owner complete");
   string root=Path.GetDirectoryName(typeof(NativeFixedImageCompositionTests).Assembly.Location);
   Check(rig.Process.Application==Path.Combine(root,"NativeCaptureFixtureChild.exe") && rig.Process.Directory==root,"actual binding uses checked fixed sibling");
   string prefix="\""+rig.Process.Application+"\" Binary 501 ";Check(rig.Process.Command.StartsWith(prefix,StringComparison.Ordinal) && SentinelProtocol.ValidToken(rig.Process.Command.Substring(prefix.Length)),"actual composed Binary command exact formatter");
   Check(Count(rig,"query")==1 && Count(rig,"create")==1 && Count(rig,"image-open")==1,"one create/query/native image lease, no second FileStream");
   Check(owner.ProcessImageObservation.Returned==true && owner.ProcessImageObservation.Agree==true && owner.ProcessImageObservation.Path==rig.ProcessPath && owner.ProcessImageObservation.ReturnedLength==(uint)rig.ProcessPath.Length,"actual successful query count and raw path retained");
   Check(owner.ExitObservation.WaitReturn==0 && owner.ExitObservation.CodeReturn==true && owner.ExitObservation.Code==0,"actual returned exit evidence");
   Check(Count(rig,"process-close")==1 && Count(rig,"thread-close")==1 && Count(rig,"sentinel-close")==1 && Count(rig,"image-close")==1,"every recording handle closes through its own adapter");
   Check(rig.Trace.IndexOf("query")<rig.Trace.IndexOf("writers") && rig.Trace.IndexOf("writers")<rig.Trace.IndexOf("pump") && rig.Trace.IndexOf("pump")<rig.Trace.IndexOf("sentinel") && rig.Trace.IndexOf("sentinel")<rig.Trace.IndexOf("thread-close") && rig.Trace.IndexOf("process-close")<rig.Trace.IndexOf("image-close"),"actual boundary ordering");
   FixedImageCompositionTestRig.RecordingFlow.AssertEmptyTransport(owner);
   Check(String.Join(",",owner.CompositionTrace)=="Run,PrepareImage,PrepareTransport,Launch,ObserveProcessImage,CloseParentWriters,Pump,ObserveExit,InspectSentinel,Refresh,Release,Refresh,CloseParentWriters","actual Run/Refresh/Release trace");
   var expected=new List<string>(new string[] {"image-open","attributes","size","identity","held-path"});
   for(int offset=0;offset<bytes.Length;offset+=65536)expected.Add("image-read");
   expected.AddRange(new string[] {"image-eof","probe-write","file-error","probe-delete","file-error","transport","sentinel-clear","sentinel-create","sentinel-error","sentinel-clear","sentinel-flags","create","query","writers","pump","wait","exit-code","sentinel","sentinel-wait","thread-close","process-close","sentinel-clear","sentinel-close","image-close"});
   Check(String.Join(",",rig.Trace.ToArray())==String.Join(",",expected.ToArray()),"complete downstream recording boundary trace; no native adapter entry");
   Check(owner.Channels[0].Capture.Total==4105 && owner.Channels[1].Capture.Total==257 && owner.SentinelProbe && owner.SentinelUnsignaled,"actual bounded Binary bytes and both EOF observations reach real capture/sentinel inspection");
   Console.WriteLine("COMPOSITION_RUN_TRACE "+String.Join(",",owner.CompositionTrace));Console.WriteLine("COMPOSITION_BOUNDARY_TRACE "+String.Join(",",rig.Trace.ToArray()));
  }
  static void QueryDiagnosticFailureStillClosesWritersPumpsAndReleases(byte[] bytes) {
   string[] faults={"query-false","query-unavailable","query-truncated","query-count","malformed","unsupported","nul","empty","different"};
   foreach(string fault in faults) {
    var rig=new FixedImageCompositionTestRig(bytes);rig.Fault=fault;
    if(fault=="malformed")rig.ProcessPath="C:\\bad\ud800";
    if(fault=="unsupported")rig.ProcessPath=@"\\server\share\image";
    if(fault=="nul")rig.ProcessPath="C:\\bad\0path";
    if(fault=="empty")rig.ProcessPath="";
    if(fault=="different")rig.ProcessPath=@"C:\different\NativeCaptureFixtureChild.exe";
    var owner=rig.CreateOwner();owner.Run();
    Check(owner.Created && owner.Unknown && owner.Released && owner.Proof.Complete && rig.Image.Released,"query-only diagnostic UNKNOWN cannot poison successful acquisition/drain/release: "+fault);
    Check(Count(rig,"query")==1 && Count(rig,"writers")==1 && Count(rig,"pump")==1 && Count(rig,"sentinel")==1 && Count(rig,"sentinel-wait")==1 && Count(rig,"image-close")==1,"query failure continues real writer/pump/sentinel/release");
    var q=owner.ProcessImageObservation;
    Check(q.Entered && q.Returned==(fault=="query-unavailable"?(bool?)null:fault=="query-false"?false:true) && q.Error==(fault=="query-false"?5U:(uint?)null),"query return/error ledger");
    // FALSE leaves the original input capacity untouched; it is not a returned count.
    uint? expectedLength=fault=="query-false" || fault=="query-unavailable"?(uint?)null:fault=="query-truncated"?32768U:fault=="query-count"?1U:(uint)rig.ProcessPath.Length;
    Check(q.ReturnedLength==expectedLength,"only known TRUE query supplies a returned count: "+fault);
    Check(q.Outcome==(fault=="query-unavailable"?"return-unavailable":fault=="query-false"?"returned-failure":fault=="different"?"different-path":"invalid-path"),"query diagnostic outcome");
    Check(q.Path==(fault=="different" || fault=="unsupported"?rig.ProcessPath:null) && q.Agree==(fault=="different"?(bool?)false:null),"invalid paths null rather than substituted expected paths");
    int count=rig.Trace.Count;owner.Release();Check(count==rig.Trace.Count && owner.Unknown,"sticky UNKNOWN after successful release");
   }
  }
  static void UnknownCreateAndInvalidOriginalsRetainWithoutQuery(byte[] bytes) {
   foreach(string fault in new string[] {"create-unavailable","process-zero","thread-zero","process-invalid","thread-invalid","create-false"}) {
    var rig=new FixedImageCompositionTestRig(bytes);rig.Fault=fault;var owner=rig.CreateOwner();owner.Run();bool knownFalse=fault=="create-false";
    Check(owner.CreateCalls==1 && owner.CreateState==(fault=="create-unavailable"?CreateEntryState.EnteredReturnUnknown:knownFalse?CreateEntryState.ReturnedFalse:CreateEntryState.ReturnedTrue),"actual create ledger");
    Check(!owner.ProcessImageObservation.Entered && owner.ProcessImageObservation.ReturnedLength==null && Count(rig,"query")==0 && Count(rig,"pump")==0 && Count(rig,"wait")==0,"unknown create/invalid originals no query/pump/exit wait");
    Check(owner.Released==knownFalse && rig.Image.Released==knownFalse && owner.Unknown,"unresolved create/original ownership retained");
    Check(Count(rig,"writers")== (knownFalse?1:0) && Count(rig,"image-close")==(knownFalse?1:0) && Count(rig,"thread-close")==0 && Count(rig,"process-close")==0,"no speculative close");
    int count=rig.Trace.Count;owner.Release();owner.ObserveExit();Check(rig.Trace.Count==count,"unknown acquisition never retried or polled");
   }
  }
  static void UnavailableExitDoesNotFabricateWaitZero(byte[] bytes) {
   foreach(string fault in new string[] {"wait-unavailable","wait-timeout","wait-failed","exit-code-unavailable","exit-code-false"}) {
    var rig=new FixedImageCompositionTestRig(bytes);rig.Fault=fault;
    rig.Wait=fault=="wait-timeout"?258U:fault=="wait-failed"?0xffffffffU:0U;
    var owner=rig.CreateOwner();owner.Run();var first=owner.ExitObservation;
    Check(first.WaitEntered && first.WaitReturn==(fault=="wait-unavailable"?(uint?)null:rig.Wait),"actual wait return, never inferred zero");
    bool code=fault.StartsWith("exit-code",StringComparison.Ordinal);
    Check(first.CodeEntered==code && first.CodeReturn==(fault=="exit-code-false"?(bool?)false:null) && first.Code==null && !owner.Proof.ExitObserved && !owner.Released,"exit unavailable/failure cannot invent code/exit/release");
    Check(first.WaitError==(fault=="wait-failed"?6U:(uint?)null) && first.CodeError==(fault=="exit-code-false"?6U:(uint?)null),"actual exit errors captured");
    rig.Fault="wait-unavailable";owner.ObserveExit();var later=owner.ExitObservation;
    Check(later.WaitReturn==null && !later.CodeEntered && later.CodeReturn==null && later.Code==null && first.WaitReturn==(fault=="wait-unavailable"?(uint?)null:rig.Wait),"later unavailable attempt clears all stale returns; prior snapshot immutable");
    rig.Fault="exit-code-unavailable";rig.Wait=0;owner.ObserveExit();Check(owner.ExitObservation.WaitReturn==0 && owner.ExitObservation.CodeEntered && owner.ExitObservation.CodeReturn==null,"known wait zero is not known exit-code return");
    rig.Fault="";rig.Code=259;owner.ObserveExit();Check(owner.Proof.ExitObserved && owner.ExitCode==259 && owner.ExitObservation.Code==259,"259 valid after actual signaled wait/code");owner.Release();Check(owner.Released,"later resolved exit allows release after actual EOF");
   }
   for(int missing=1;missing<=3;missing++) {
    var incomplete=new FixedImageCompositionTestRig(bytes);incomplete.StdoutEof=(missing&1)==0;incomplete.StderrEof=(missing&2)==0;var retained=incomplete.CreateOwner();retained.Run();
    Check(retained.Proof.CanRelease && retained.Proof.ExitObserved && !retained.Released && Count(incomplete,"image-close")==0 && Count(incomplete,"thread-close")==0,"each composed EOF guard adds to old CanRelease without fabricating EOF");
    incomplete.Flow.Recover(retained);Check(Count(incomplete,"recover")==1 && Count(incomplete,"image-close")==0,"real bounded recovery with terminal empty slots never closes retained image");
   }
  }
  static void ImageCloseFailureRetainsWholeOwner(byte[] bytes) {
   foreach(string fault in new string[] {"image-close-false","image-close-unavailable","thread-close-false","thread-close-unavailable","process-close-false","process-close-unavailable"}) {
    var rig=new FixedImageCompositionTestRig(bytes);rig.Fault=fault;var owner=rig.CreateOwner();owner.Run();
    Check(!owner.Released && !owner.Proof.HandlesClosed && owner.Unknown && !rig.Image.Released,"unresolved checked close retains whole owner");
    if(fault.StartsWith("image",StringComparison.Ordinal))Check(rig.Image.Observation.CloseState==(fault.EndsWith("false",StringComparison.Ordinal)?"returned-failure":"return-unknown"),"actual image close ledger");
    else Check(Count(rig,"image-close")==0,"process/thread close failure stops image close");
    var observation=owner.ReleaseObservation;Check(observation.Attempted && !observation.Released,"real release immutable ledger");
    if(fault.StartsWith("thread",StringComparison.Ordinal))Check(observation.ThreadCloseEntered && observation.ThreadCloseReturn==(fault.EndsWith("false",StringComparison.Ordinal)?(bool?)false:null) && observation.ThreadCloseError==(fault.EndsWith("false",StringComparison.Ordinal)?6U:(uint?)null) && !observation.ProcessCloseEntered,"exact thread close return/error before process close");
    if(fault.StartsWith("process",StringComparison.Ordinal))Check(observation.ThreadCloseReturn==true && observation.ProcessCloseEntered && observation.ProcessCloseReturn==(fault.EndsWith("false",StringComparison.Ordinal)?(bool?)false:null) && observation.ProcessCloseError==(fault.EndsWith("false",StringComparison.Ordinal)?6U:(uint?)null),"exact process close return/error");
    int count=rig.Trace.Count;owner.Release();Check(count==rig.Trace.Count,"no close retry after FALSE/unavailable");
   }
  }
  static void MixedNativeAndRecordingDomainsAreRejected(byte[] bytes) {
   var rig=new FixedImageCompositionTestRig(bytes);var other=new FixedImageCompositionTestRig(bytes);
   Reject(delegate { new ChildCaptureOwner(rig.Image); },"native bindings reject recording image");
   Reject(delegate { new ChildCaptureOwner(FixedFixtureImage.CreateForObservation(),rig.Bindings); },"recording bindings reject native image");
   Reject(delegate { new ChildCaptureOwner(other.Image,rig.Bindings); },"different recording domains rejected");
   Reject(delegate { new ChildCaptureOwner(null,rig.Bindings); },"null image");Reject(delegate { new ChildCaptureOwner(rig.Image,null); },"null bindings");
   Reject(delegate { FixedImageCompositionBindings.CreateRecording(rig.Image,ChildCaptureProcessCalls.Instance,rig.Flow,rig.Sentinel); },"native process rejected");
   Reject(delegate { FixedImageCompositionBindings.CreateRecording(rig.Image,rig.Process,ChildCaptureFlow.Instance,rig.Sentinel); },"native flow rejected");
   Reject(delegate { FixedImageCompositionBindings.CreateRecording(rig.Image,rig.Process,rig.Flow,new SentinelNativeCalls()); },"native sentinel rejected");
   Reject(delegate { FixedImageCompositionBindings.CreateRecording(rig.Image,rig.Process,rig.Flow,other.Sentinel); },"foreign recording sentinel rejected");
   Reject(delegate { FixedImageCompositionBindings.CreateRecording(rig.Image,other.Process,rig.Flow,rig.Sentinel); },"foreign recording process rejected");
   Reject(delegate { FixedImageCompositionBindings.CreateRecording(rig.Image,rig.Process,other.Flow,rig.Sentinel); },"foreign recording flow rejected");
   Check(rig.Trace.Count==0 && other.Trace.Count==0,"domain rejections precede all native calls and claims");var owner=rig.CreateOwner();owner.Run();Check(owner.Released,"rejected mismatches did not consume claim");
  }
  static void SerializedMatrix(byte[] bytes) {
   string[] faults={"ok","digest","size","missing","probe-error","probe-success","probe-write-unavailable","probe-delete-unavailable","probe-close-false","probe-close-unavailable","image-open-unavailable","image-read-unavailable","image-read-false",
    "create-false","create-unavailable","process-zero","thread-zero","process-invalid","thread-invalid",
    "query-false","query-unavailable","query-truncated","query-count","malformed","unsupported","nul","empty","different",
    "wait-unavailable","wait-timeout","wait-failed","exit-code-unavailable","exit-code-false","image-close-false","image-close-unavailable","thread-close-false","thread-close-unavailable","process-close-false","process-close-unavailable","stdout-eof-missing","stderr-eof-missing"};
   foreach(string fault in faults) {
    var rig=new FixedImageCompositionTestRig(bytes);rig.Fault=fault;
    if(fault=="malformed")rig.ProcessPath="C:\\bad\ud800";
    if(fault=="unsupported")rig.ProcessPath=@"\\server\share\image";
    if(fault=="nul")rig.ProcessPath="C:\\bad\0path";
    if(fault=="empty")rig.ProcessPath="";
    if(fault=="different")rig.ProcessPath=@"C:\different\NativeCaptureFixtureChild.exe";
    if(fault=="wait-timeout")rig.Wait=258;
    if(fault=="wait-failed")rig.Wait=0xffffffff;
    rig.StdoutEof=fault!="stdout-eof-missing";rig.StderrEof=fault!="stderr-eof-missing";
    var owner=rig.CreateOwner();owner.Run();var originals=owner.OriginalHandlesObservation;
    int calls=rig.Trace.Count;int rounds=owner.Rounds;bool released=owner.Released;
    try { owner.Run(); } catch(InvalidOperationException) { owner.OneShotRefused=true; }
    Check(owner.OneShotRefused && calls==rig.Trace.Count && owner.Rounds==rounds && owner.Released==released,"serialized one-shot assertion has no side effects");
    Check(originals.State==owner.OriginalHandlesObservation.State,"original validity observation immutable after repeated refusal");
    if(fault=="ok")Check(originals.State=="valid" && owner.Original.Process==IntPtr.Zero && owner.Original.Thread==IntPtr.Zero,"recorded validity survives real successful release");
    if(fault=="create-unavailable")Check(originals.State=="not-observed","unknown acquisition never becomes validity");
    if(fault=="process-zero" || fault=="thread-zero" || fault=="process-invalid" || fault=="thread-invalid")Check(originals.State=="invalid","invalid originals stay invalid");
    var snapshot=owner.CompositionSnapshot("matching-image",false);string frozen=snapshot.Json;
    owner.Release();Check(snapshot.Json==frozen,"wire snapshot immutable even after later owner call");
    Console.WriteLine("COMPOSED_DIAGNOSTIC "+fault+" "+snapshot.Json);
   }
  }
  public static int RunManaged(byte[] pristineBytes) {
   Reject(delegate { new FixedImageCompositionTestRig(null); },"null pristine rejected");Reject(delegate { new FixedImageCompositionTestRig(new byte[0]); },"empty pristine rejected");
   byte[] wrong=(byte[])pristineBytes.Clone();wrong[0]^=1;Reject(delegate { new FixedImageCompositionTestRig(wrong); },"same-length fake pristine cannot override expectations");
   RealConstructorClaimsOnce(pristineBytes);RealRunRefusesBeforeTransportOrCreate(pristineBytes);RealRunIsOneShot(pristineBytes);
   SharedCommandFormatterPreservesLegacyBytes(pristineBytes);RealLaunchUsesFixedBindingAndOriginalHandles(pristineBytes);
   QueryDiagnosticFailureStillClosesWritersPumpsAndReleases(pristineBytes);UnknownCreateAndInvalidOriginalsRetainWithoutQuery(pristineBytes);
   UnavailableExitDoesNotFabricateWaitZero(pristineBytes);ImageCloseFailureRetainsWholeOwner(pristineBytes);MixedNativeAndRecordingDomainsAreRejected(pristineBytes);
   SerializedMatrix(pristineBytes);
   Console.WriteLine("PASS fixed image composition owners");return 0;
  }
 }
}
