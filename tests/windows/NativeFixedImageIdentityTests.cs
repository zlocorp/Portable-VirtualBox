// TEST ONLY: pure modeled native returns, never manufacture uncertain native calls.
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
   ProbeContracts();
   for(int mode=0;mode<3;mode++)Console.WriteLine("PROBE_DIAGNOSTIC "+ProbeFaultReport(mode));
   string unicode=UnicodeReport();
   foreach(char c in unicode)Check(c<=127,"ASCII-only JSON preserves actual Unicode path across console encodings");
   Console.WriteLine("SERIALIZER_UNICODE "+unicode);
   Console.WriteLine("PASS fixed image managed contracts");return 0;
  }
 }
}
