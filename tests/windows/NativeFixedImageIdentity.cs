// TEST ONLY: exact harmless sibling observations, no launcher or admission authority.
using System;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
namespace PortableVBox {
 internal sealed class FixedImageExpectation {
  internal readonly long Length;
  internal readonly string Sha256;
  internal FixedImageExpectation(long length,string sha256) {
   if(length<=0 || length>FixedImageState.MaxImage || sha256==null || !Regex.IsMatch(sha256,@"\A[0-9a-f]{64}\z"))throw new ArgumentException("Invalid compiled expectation");
   Length=length;Sha256=sha256;
  }
  internal static string Source(long length,string sha256) {
   var checkedValue=new FixedImageExpectation(length,sha256);
   return "// Generated from completed pristine harmless build bytes. TEST ONLY.\nnamespace PortableVBox { internal static class FixedFixtureBuildExpectation { internal const string Name = \"NativeCaptureFixtureChild.exe\"; internal const long Length = "+checkedValue.Length.ToString(CultureInfo.InvariantCulture)+"L; internal const string Sha256 = \""+checkedValue.Sha256+"\"; } }\n";
  }
  internal static FixedImageExpectation ParseSource(string source) {
   if(source==null || new UTF8Encoding(false,true).GetByteCount(source)>2048)throw new ArgumentException("Expectation source bound");
   Match m=Regex.Match(source,@"internal const long Length = ([1-9][0-9]*)L; internal const string Sha256 = ""([0-9a-f]{64})"";");
   long length;
   if(!m.Success || !Int64.TryParse(m.Groups[1].Value,NumberStyles.None,CultureInfo.InvariantCulture,out length))throw new ArgumentException("Expectation syntax");
   var result=new FixedImageExpectation(length,m.Groups[2].Value);
   if(source!=Source(result.Length,result.Sha256))throw new ArgumentException("Expectation syntax");
   return result;
  }
 }
 internal static class FixedImageCodec {
  internal static void Leaf(uint attributes) { if((attributes & (0x10U|0x400U))!=0)throw new ArgumentException("Unsupported directory/reparse leaf"); }
  internal static string Hex(byte[] bytes) { var s=new StringBuilder(bytes.Length*2);foreach(byte b in bytes)s.Append(b.ToString("x2",CultureInfo.InvariantCulture));return s.ToString(); }
  internal static string LocalPath(string value) { return FixedImagePath.Validate(value); }
  internal static string FinalPath(string value,uint returned) {
   if(returned==0 || returned>=32768 || value==null || returned!=value.Length)throw new ArgumentException("Failed/truncated path return");
   return LocalPath(value);
  }
  internal static string Q(string value) {
   if(value==null)return "null";
   var b=new StringBuilder("\"");foreach(char c in value) {
    if(c=='"' || c=='\\') { b.Append('\\');b.Append(c); }
    else if(c<32 || c>=127)b.Append("\\u"+((int)c).ToString("x4",CultureInfo.InvariantCulture));
    else b.Append(c);
   }return b.Append('"').ToString();
  }
  internal static string N(long? value) { return value.HasValue?value.Value.ToString(CultureInfo.InvariantCulture):"null"; }
 }
 internal sealed class FixedImageObservation {
  internal readonly string OpenState,ReadState,CloseState,ActualSha256,VolumeSerial,FileId,HeldPath,Refusal;
  internal readonly uint? OpenError,ReadError;
  internal readonly long? ActualSize;
  internal readonly long BytesHashed;
  internal readonly int? EofRequestBytes;
  internal readonly uint? EofReturnBytes;
  internal FixedImageObservation(FixedImageState s) {
   OpenState=s.OpenState;ReadState=s.ReadState;CloseState=s.CloseState;ActualSha256=s.ActualSha256;
   VolumeSerial=s.VolumeSerial;FileId=s.FileId;HeldPath=s.HeldPath;Refusal=s.Refusal;
   OpenError=s.OpenError;ReadError=s.ReadError;ActualSize=s.ActualSize;BytesHashed=s.BytesHashed;
   EofRequestBytes=s.EofRequestBytes;EofReturnBytes=s.EofReturnBytes;
  }
 }
 // Pure return ledger. Synthetic tests cannot reach a native file or launch entry.
 internal sealed class FixedImageState {
  internal const long MaxImage=16777216;
  internal const int Chunk=65536;
  internal readonly FixedImageExpectation Expected;
  internal string OpenState { get; private set; }
  internal string ReadState { get; private set; }
  internal string CloseState { get; private set; }
  internal uint? OpenError { get; private set; }
  internal uint? ReadError { get; private set; }
  internal long? ActualSize { get; private set; }
  internal string ActualSha256 { get; private set; }
  internal long BytesHashed { get; private set; }
  internal int? EofRequestBytes { get; private set; }
  internal uint? EofReturnBytes { get; private set; }
  internal string VolumeSerial { get; private set; }
  internal string FileId { get; private set; }
  internal string HeldPath { get; private set; }
  internal string Refusal { get; private set; }
  int request,pendingHash;
  bool terminal,prepared;
  internal FixedImageState(FixedImageExpectation expected) { Expected=expected;OpenState="not-entered";ReadState="not-entered";CloseState="not-opened";Refusal="observation-failure"; }
  internal FixedImageObservation Snapshot() { return new FixedImageObservation(this); }
  internal void BeginPreparation() { if(prepared)throw new InvalidOperationException("Preparation one-shot");prepared=true; }
  internal void EnterOpen() { if(OpenState!="not-entered")throw new InvalidOperationException("Open one-shot");OpenState="return-unknown"; }
  internal void ReturnOpen(bool success,uint? error) {
   if(OpenState!="return-unknown" || success==error.HasValue)throw new InvalidOperationException("Open return contract");
   OpenState=success?"returned-success":"returned-failure";OpenError=error;CloseState=success?"not-entered":"not-opened";
   if(!success && error==2)Refusal="missing-image";
  }
  internal void ObserveSize(long size) {
   if(OpenState!="returned-success" || ActualSize.HasValue || size<0)throw new InvalidOperationException("Size contract");ActualSize=size;
   if(size<=0 || size>MaxImage || size!=Expected.Length)Refusal="size-mismatch";
  }
  internal void ObserveIdentity(bool supported,ulong volume,ulong low,ulong high) {
   if(!supported)throw new ArgumentException("Unsupported file identity");
   VolumeSerial=volume.ToString("x16",CultureInfo.InvariantCulture);
   byte[] bytes=new byte[16];Array.Copy(BitConverter.GetBytes(low),0,bytes,0,8);Array.Copy(BitConverter.GetBytes(high),0,bytes,8,8);FileId=FixedImageCodec.Hex(bytes);
  }
  internal void ObservePath(string value,uint count) { HeldPath=FixedImageCodec.FinalPath(value,count); }
  internal void EnterRead(int count) {
   if(OpenState!="returned-success" || CloseState!="not-entered" || ActualSize!=Expected.Length || ActualSize<=0 || ActualSize>MaxImage || count<=0 || count>Chunk || pendingHash!=0 || terminal || (ReadState!="not-entered" && ReadState!="known-incomplete"))throw new InvalidOperationException("Read entry contract");
   if(BytesHashed<Expected.Length && count>Expected.Length-BytesHashed)throw new InvalidOperationException("Read remaining bound");
   if(BytesHashed==Expected.Length && count!=1)throw new InvalidOperationException("Positive one-byte terminal request required");
   request=count;ReadState="return-unknown";
  }
  internal void ReturnRead(bool success,uint count,uint? error) {
   if(ReadState!="return-unknown" || success==error.HasValue)throw new InvalidOperationException("Read return contract");
   ReadState=success?"known-incomplete":"returned-failure";ReadError=error;
   if(!success) { terminal=true;return; }
   if(BytesHashed==Expected.Length || count==0) { EofRequestBytes=request;EofReturnBytes=count;terminal=true;return; }
   if(count>(uint)request || count>Expected.Length-BytesHashed || BytesHashed+count>MaxImage) { terminal=true;return; }
   pendingHash=(int)count;
  }
  internal void AcceptHashed(int count) {
   if(count<=0 || pendingHash!=count || ReadState!="known-incomplete" || terminal)throw new InvalidOperationException("Hash accepted bytes contract");
   BytesHashed=checked(BytesHashed+count);pendingHash=0;
  }
  internal void CompleteHash(string digest) {
   if(ReadState!="known-incomplete" || pendingHash!=0 || BytesHashed!=Expected.Length || EofRequestBytes!=1 || EofReturnBytes!=0)throw new InvalidOperationException("Complete digest requires exact bytes and positive EOF proof");
   new FixedImageExpectation(Expected.Length,digest);ActualSha256=digest;ReadState="complete";
   Refusal=digest==Expected.Sha256?"none":"digest-mismatch";
  }
  internal void HashFailed() { if(ReadState=="return-unknown")throw new InvalidOperationException("Unknown native read remains unknown");ReadState="known-incomplete";ActualSha256=null;ReadError=null;terminal=true;pendingHash=0;Refusal="observation-failure"; }
  internal bool CanRelease { get { return OpenState=="returned-success" && ReadState!="return-unknown" && CloseState=="not-entered"; } }
  internal bool Released { get { return CloseState=="returned-success" || (OpenState=="returned-failure" && CloseState=="not-opened") || OpenState=="not-entered"; } }
  internal void EnterClose() { if(!CanRelease)throw new InvalidOperationException("Close forbidden or one-shot");CloseState="return-unknown"; }
  internal void ReturnClose(bool success) { if(CloseState!="return-unknown")throw new InvalidOperationException("Close return without entry");CloseState=success?"returned-success":"returned-failure"; }
 }
 internal static class FixedImageNative {
  [StructLayout(LayoutKind.Sequential)] internal struct AttributeTag { internal uint Attributes,Tag; }
  [StructLayout(LayoutKind.Sequential)] internal struct IdInfo { internal ulong Volume,Low,High; }
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true,ExactSpelling=true)]
  internal static extern IntPtr CreateFileW(string name,uint access,uint share,IntPtr security,uint disposition,uint flags,IntPtr template);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool GetFileSizeEx(IntPtr handle,out long size);
  [DllImport("kernel32.dll",SetLastError=true,EntryPoint="GetFileInformationByHandleEx")] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool Attributes(IntPtr handle,int info,out AttributeTag value,uint size);
  [DllImport("kernel32.dll",SetLastError=true,EntryPoint="GetFileInformationByHandleEx")] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool Identity(IntPtr handle,int info,out IdInfo value,uint size);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true,ExactSpelling=true)] internal static extern uint GetFinalPathNameByHandleW(IntPtr handle,StringBuilder buffer,uint length,uint flags);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool ReadFile(IntPtr handle,byte[] bytes,uint request,out uint read,IntPtr overlapped);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool CloseHandle(IntPtr handle);
 }
 internal sealed class FixedImageProbeCall {
  internal readonly uint Access,Share,Disposition;
  internal FixedImageProbeCall(uint access,uint share,uint disposition) { FixedImageProbe.ValidateCall(access,share,disposition);Access=access;Share=share;Disposition=disposition; }
 }
 // Pure probe return ledger, also consumed by every actual native probe call.
 // Tests leave entered returns unknown; they never manufacture uncertain handles.
 internal sealed class FixedImageProbeState {
  internal string OpenState { get; private set; }
  internal uint? OpenError { get; private set; }
  internal string CloseState { get; private set; }

  internal FixedImageProbeState() {
   OpenState="not-entered";
   CloseState="not-opened";
  }

  internal bool CanClose {
   get { return OpenState=="returned-success" && CloseState=="not-entered"; }
  }
  internal bool Resolved {
   get { return OpenState=="returned-failure" || CloseState=="returned-success"; }
  }
  internal bool Denied {
   get { return OpenState=="returned-failure" && OpenError==32 && CloseState=="not-opened"; }
  }

  internal void EnterOpen() {
   if(OpenState!="not-entered")throw new InvalidOperationException("Probe open one-shot");
   OpenState="return-unknown";
  }

  internal void ReturnOpen(bool success,uint? error) {
   if(OpenState!="return-unknown" || success==error.HasValue)
    throw new InvalidOperationException("Probe open return contract");
   OpenError=error;
   OpenState=success?"returned-success":"returned-failure";
   CloseState=success?"not-entered":"not-opened";
  }

  internal void EnterClose() {
   if(!CanClose)throw new InvalidOperationException("Probe close forbidden or one-shot");
   CloseState="return-unknown";
  }

  internal void ReturnClose(bool success) {
   if(CloseState!="return-unknown")throw new InvalidOperationException("Probe close return without entry");
   CloseState=success?"returned-success":"returned-failure";
  }

  internal string Json(FixedImageProbeCall call) {
   return "{\"access\":"+FixedImageCodec.Q(call.Access==0x40000000?"GENERIC_WRITE":"DELETE")+
    ",\"share\":"+FixedImageCodec.N(call.Share)+",\"disposition\":"+FixedImageCodec.N(call.Disposition)+
    ",\"open_state\":"+FixedImageCodec.Q(OpenState)+",\"open_error\":"+FixedImageCodec.N(OpenError)+
    ",\"close_state\":"+FixedImageCodec.Q(CloseState)+"}";
  }
 }
 internal sealed class FixedImageProbe {
  readonly FixedImageProbeCall call;
  readonly FixedImageProbeState state=new FixedImageProbeState();
  IntPtr handle;

  internal FixedImageProbe(uint access) {
   call=new FixedImageProbeCall(access,7,3);
  }
  internal static void ValidateCall(uint access,uint share,uint disposition) {
   if((access!=0x40000000 && access!=0x10000) || share!=7 || disposition!=3)
    throw new ArgumentException("Exact compatible probe contract required");
  }
  internal bool Resolved { get { return state.Resolved; } }
  internal bool Denied { get { return state.Denied; } }

  internal void Run() {
   string fixedPath=Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location),FixedFixtureBuildExpectation.Name);
   state.EnterOpen();
   IntPtr result=FixedImageNative.CreateFileW(fixedPath,call.Access,call.Share,IntPtr.Zero,call.Disposition,0,IntPtr.Zero);
   if(result==new IntPtr(-1)) {
    uint error=unchecked((uint)Marshal.GetLastWin32Error());
    state.ReturnOpen(false,error);
    return;
   }
   // Store the exact successful handle before recording the return or closing it.
   handle=result;
   state.ReturnOpen(true,null);
   // Unexpected success always fails the sharing assertion, even after TRUE close.
   state.EnterClose();
   bool closed=FixedImageNative.CloseHandle(handle);
   state.ReturnClose(closed);
   GC.KeepAlive(this);
  }

  internal string Json() {
   return state.Json(call);
  }
 }
 internal sealed class FixedFixtureImage {
  readonly FixedImageState state;
  readonly string fixedPath;
  IntPtr handle;
  FixedImageProbe writeProbe,deleteProbe;
  FixedFixtureImage() {
   if(FixedFixtureBuildExpectation.Name!="NativeCaptureFixtureChild.exe")throw new InvalidOperationException("Compiled sibling name");
   state=new FixedImageState(new FixedImageExpectation(FixedFixtureBuildExpectation.Length,FixedFixtureBuildExpectation.Sha256));
   fixedPath=Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location),FixedFixtureBuildExpectation.Name);
  }
  internal static FixedFixtureImage CreateForObservation() { return new FixedFixtureImage(); }
  internal FixedImageObservation Observation { get { return state.Snapshot(); } }
  internal FixedImageExpectation Expected { get { return state.Expected; } }
  internal bool Ready { get { return state.Refusal=="none" && state.ReadState=="complete" && state.VolumeSerial!=null && state.FileId!=null && state.HeldPath!=null; } }
  internal bool Released { get { return state.Released && (writeProbe==null || writeProbe.Resolved) && (deleteProbe==null || deleteProbe.Resolved); } }
  internal void PrepareOnce() {
   state.BeginPreparation();
   state.EnterOpen();
   IntPtr result=FixedImageNative.CreateFileW(fixedPath,0x80000000,1,IntPtr.Zero,3,0x00200000,IntPtr.Zero);
   if(result==new IntPtr(-1)) { uint error=unchecked((uint)Marshal.GetLastWin32Error());state.ReturnOpen(false,error);return; }
   handle=result;state.ReturnOpen(true,null);
   FixedImageNative.AttributeTag attributes;
   if(!FixedImageNative.Attributes(handle,9,out attributes,8))throw new IOException("Leaf attributes unavailable");FixedImageCodec.Leaf(attributes.Attributes);
   long size;if(!FixedImageNative.GetFileSizeEx(handle,out size))throw new IOException("Size query unavailable");state.ObserveSize(size);
   if(size<=0 || size>FixedImageState.MaxImage || size!=state.Expected.Length)return;
   FixedImageNative.IdInfo id;
   bool known=FixedImageNative.Identity(handle,18,out id,24);state.ObserveIdentity(known,id.Volume,id.Low,id.High);
   var path=new StringBuilder(32768);uint count=FixedImageNative.GetFinalPathNameByHandleW(handle,path,32768,0);state.ObservePath(path.ToString(),count);
   using(var sha=SHA256.Create()) {
    byte[] bytes=new byte[FixedImageState.Chunk];
    while(state.BytesHashed<state.Expected.Length) {
     int request=(int)Math.Min(bytes.Length,state.Expected.Length-state.BytesHashed);uint read;
     state.EnterRead(request);
     bool success=FixedImageNative.ReadFile(handle,bytes,(uint)request,out read,IntPtr.Zero);
     uint? error=success?(uint?)null:unchecked((uint)Marshal.GetLastWin32Error());state.ReturnRead(success,read,error);
     if(!success || read==0 || read>(uint)request)return;
     try { sha.TransformBlock(bytes,0,(int)read,bytes,0);state.AcceptHashed((int)read); }
     catch { state.HashFailed();throw; }
    }
    state.EnterRead(1);uint terminal;
    bool eof=FixedImageNative.ReadFile(handle,bytes,1,out terminal,IntPtr.Zero);
    uint? eofError=eof?(uint?)null:unchecked((uint)Marshal.GetLastWin32Error());state.ReturnRead(eof,terminal,eofError);
    if(!eof || terminal!=0)return;
    try { sha.TransformFinalBlock(new byte[0],0,0);state.CompleteHash(FixedImageCodec.Hex(sha.Hash)); }
    catch { state.HashFailed();throw; }
   }
   GC.KeepAlive(this);
  }
  internal bool ObserveSharing() {
   if(!Ready || !state.CanRelease || writeProbe!=null || deleteProbe!=null)throw new InvalidOperationException("Positive held-image probes only, one-shot");
   writeProbe=new FixedImageProbe(0x40000000);writeProbe.Run();
   if(!writeProbe.Resolved)return false;
   deleteProbe=new FixedImageProbe(0x10000);deleteProbe.Run();
   return writeProbe.Denied && deleteProbe.Denied;
  }
  internal bool TryRelease() {
   if(Released)return true;
   if(!state.CanRelease || (writeProbe!=null && !writeProbe.Resolved) || (deleteProbe!=null && !deleteProbe.Resolved))return false;
   state.EnterClose();bool success=FixedImageNative.CloseHandle(handle);state.ReturnClose(success);GC.KeepAlive(this);return success;
  }
  internal string Report(string scenario,bool passed) {
   return FixedImageEvidence.Report(Expected,Observation,scenario,passed,writeProbe==null?"null":writeProbe.Json(),deleteProbe==null?"null":deleteProbe.Json());
  }
 }
 internal static class FixedImageEvidence {
  internal static string Report(FixedImageExpectation Expected,FixedImageObservation o,string scenario,bool passed,string write,string delete) {
   return "{\"kind\":\"fixed_image_case\",\"schema\":1,\"stage\":\"file-only\",\"case\":"+FixedImageCodec.Q(scenario)+",\"status\":"+FixedImageCodec.Q(passed?"PASS":"FAIL")+",\"mutation_authorized\":false,\"refusal\":"+FixedImageCodec.Q(o.Refusal)+",\"create_calls\":0,\"expected_size\":"+FixedImageCodec.N(Expected.Length)+",\"expected_sha256\":"+FixedImageCodec.Q(Expected.Sha256)+",\"open_state\":"+FixedImageCodec.Q(o.OpenState)+",\"open_error\":"+FixedImageCodec.N(o.OpenError)+",\"actual_size\":"+FixedImageCodec.N(o.ActualSize)+",\"actual_sha256\":"+FixedImageCodec.Q(o.ActualSha256)+",\"bytes_hashed\":"+FixedImageCodec.N(o.BytesHashed)+",\"read_state\":"+FixedImageCodec.Q(o.ReadState)+",\"read_error\":"+FixedImageCodec.N(o.ReadError)+",\"eof_request_bytes\":"+FixedImageCodec.N(o.EofRequestBytes)+",\"eof_return_bytes\":"+FixedImageCodec.N(o.EofReturnBytes)+",\"volume_serial\":"+FixedImageCodec.Q(o.VolumeSerial)+",\"file_id\":"+FixedImageCodec.Q(o.FileId)+",\"held_path\":"+FixedImageCodec.Q(o.HeldPath)+",\"write_probe\":"+write+",\"delete_probe\":"+delete+",\"close_state\":"+FixedImageCodec.Q(o.CloseState)+",\"process_observation\":null}";
  }
 }
}
