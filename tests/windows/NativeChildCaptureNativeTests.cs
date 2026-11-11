// TEST ONLY. Expected fixture bytes are checked against independent OS observations.
using System;
namespace PortableVBox {
 public static class NativeChildCaptureNativeTests {
  static readonly ChildCaptureOwner[] roots=new ChildCaptureOwner[9];
  static int assertion;
  static void Check(bool value) { ++assertion;if(!value) throw new InvalidOperationException("Native fixed-child assertion failed"); }
  static ulong Expected(int length,int seed,bool header) {
   ulong hash=14695981039346656037UL;
   if(header) foreach(byte value in new byte[]{80,86,67,50,1,0,0,165}) hash=unchecked((hash^value)*1099511628211UL);
   for(int i=0;i<length;i++) hash=unchecked((hash^(byte)((i*31+seed)&255))*1099511628211UL);
   return hash;
  }
  static void AssertCase(ChildCaptureOwner owner) {
   int a=17,b=257;uint exit=0;
   switch(owner.Scenario) {
    case CaptureCase.Empty: a=0;b=0;break;
    case CaptureCase.Binary: a=4097;break;
    case CaptureCase.Large: case CaptureCase.CaptureFault: case CaptureCase.EvidenceFault: a=196731;b=204829;break;
    case CaptureCase.Nonzero: exit=23;break;
    case CaptureCase.Exit259: exit=259;break;
   }
   bool expectedUnknown=owner.Scenario==CaptureCase.PostCreateFault || owner.Scenario==CaptureCase.CaptureFault || owner.Scenario==CaptureCase.EvidenceFault || owner.Scenario==CaptureCase.WithheldEof;
   Check(owner.Created && owner.Proof.Complete && owner.Released && owner.ExitCode==exit && owner.Unknown==expectedUnknown);
   int expectedFault=owner.Scenario==CaptureCase.PostCreateFault?1:owner.Scenario==CaptureCase.CaptureFault?2:owner.Scenario==CaptureCase.EvidenceFault?3:0;
   Check(owner.FaultSite==expectedFault && owner.EvidenceBytesWritten==(owner.Scenario==CaptureCase.EvidenceFault?1:0));
   Check(owner.CreateCalls==1 && owner.WaitCalls>=1 && owner.ExitCodeReads>=1);
   Check(owner.SentinelProbe && owner.SentinelUnsignaled);
   if(expectedFault==2 || expectedFault==3)
    Check(owner.Channels[0].Capture.Unknown && owner.Channels[0].Capture.RetainedCount>=8 && owner.Channels[0].Capture.RetainedCount<=4103 && owner.Channels[0].Capture.Discarded>0);
   Check(owner.HeldWriterBlockedEof==(owner.Scenario==CaptureCase.WithheldEof));
   Check(owner.Channels[0].Capture.Total==a+(owner.Scenario==CaptureCase.Empty?0:8) && owner.Channels[1].Capture.Total==b);
   Check(owner.Channels[0].Capture.Hash==Expected(a,0,owner.Scenario!=CaptureCase.Empty) && owner.Channels[1].Capture.Hash==Expected(b,71,false));
   for(int i=0;i<2;i++) {
    ChildCaptureChannel channel=owner.Channels[i];
    Check(channel.Capture.RetainedCount<=65536 && channel.Capture.Eof && channel.Read.Proof.SafeToRelease && channel.Connect.Proof.SafeToRelease);
    Check(channel.Visits==owner.Rounds && channel.MaxGap<=1 && channel.Read.Released && channel.Connect.Released);
   }
   int rounds=owner.Rounds;
   try { owner.Run(); } catch(InvalidOperationException) { owner.OneShotRefused=true; }
   Check(owner.OneShotRefused && owner.Rounds==rounds && owner.Released);
  }
  public static int Main(string[] args) {
   if(args.Length!=0 || Environment.OSVersion.Platform!=PlatformID.Win32NT || IntPtr.Size!=8) return 2;
   int failed=0,completed=0;bool allReleased=true;
   // Root all owners before the first native operation; never remove unresolved ones.
   for(int i=0;i<roots.Length;i++) roots[i]=new ChildCaptureOwner((CaptureCase)i);
   for(int i=0;i<roots.Length;i++) {
    ChildCaptureOwner owner=roots[i];bool passed=false;assertion=0;
    try { owner.Run();AssertCase(owner);passed=true; } catch { ++failed;owner.AssertionFailedAt=assertion==0?-1:assertion; }
    allReleased=allReleased && owner.Released;++completed;
    Console.WriteLine(owner.Report(passed));
    if(!owner.Released) break; // Retain unresolved owner; do not multiply native uncertainty.
   }
   Console.WriteLine("{\"kind\":\"native_child_summary\",\"status\":\""+(failed==0 && completed==9 && allReleased?"PASS":"FAIL")+
    "\",\"cases\":"+ChildCaptureOwner.N(completed)+",\"failed\":"+ChildCaptureOwner.N(failed)+
    ",\"all_owners_released\":"+ChildCaptureOwner.B(allReleased)+",\"mutation_authorized\":false}");
   GC.KeepAlive(roots);
   return failed==0 && completed==9 && allReleased?0:1;
  }
 }
}
