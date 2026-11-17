// TEST ONLY: independently compare fixed-child observations, never authorize mutation.
using System;
using System.IO;
namespace PortableVBox {
 public static class NativeLaunchEnvironmentNativeTests {
  static readonly ChildCaptureOwner[] roots=new ChildCaptureOwner[3];
  static int check;
  static void Check(bool value) { ++check;if(!value) throw new InvalidOperationException("Environment observation assertion failed: "+check); }
  sealed class ThrowingDiagnostic : Stream {
   readonly MemoryStream data=new MemoryStream();
   readonly int fault;
   internal ThrowingDiagnostic(int value) { fault=value; }
   public override bool CanRead { get { return false; } }
   public override bool CanSeek { get { return false; } }
   public override bool CanWrite { get { return true; } }
   public override long Position { get { throw new NotSupportedException(); } set { throw new NotSupportedException(); } }
   public override int Read(byte[] bytes,int offset,int count) { throw new NotSupportedException(); }
   public override long Seek(long offset,SeekOrigin origin) { throw new NotSupportedException(); }
   public override void SetLength(long length) { throw new NotSupportedException(); }
   public override void Write(byte[] bytes,int offset,int count) { for(int i=0;i<count;i++)WriteByte(bytes[offset+i]); }
   public override long Length { get { throw new IOException("Diagnostic length unavailable"); } }
   public override void WriteByte(byte value) { if(fault==0) throw new IOException("Diagnostic write unavailable");data.WriteByte(value); }
   public override void Flush() { if(fault==1) throw new IOException("Diagnostic flush unavailable");data.Flush(); }
  }
  public static int RunManaged() {
   NativeLaunchEnvironmentTests.Main();
   NativeLaunchEnvironmentPolicyTests.RunManaged();
   NativeLaunchEnvironmentObservationTests.RunManaged();
   byte[] record=EnvironmentObservation.FromBlock(delegate(int index) {
    return ("PVBOX_FIXTURE_TEXT=Привет = fixture \U0001F642\0PVBOX_FIXTURE_EMPTY=\0SystemRoot=C:\\Windows\0WINDIR=C:\\Windows\0\0")[index];
   }).Encode();
   var capture=new PipeCapture();var proof=new ChildCaptureProof();var sink=new MemoryStream();
   byte[] first=new byte[12];Array.Copy(record,first,first.Length);capture.Receive(first,first.Length);
   Check(!EnvironmentEvidenceSink.TryWrite(sink));proof.Fault();
   Check(capture.RetainedCount<record.Length && sink.Length==1 && proof.Unknown);
   byte[] last=new byte[record.Length-first.Length];Array.Copy(record,first.Length,last,0,last.Length);capture.Receive(last,last.Length);
   byte[] full=new byte[capture.RetainedCount];Array.Copy(capture.Retained,full,full.Length);
   EnvironmentObservation actual=EnvironmentObservation.Parse(full);
   Check(actual.Text==FixedEnvironmentPolicy.Text && actual.EmptyPresent && actual.Empty=="" && !actual.SentinelPresent);
   Check(full.Length==record.Length && capture.Discarded==0 && !capture.Unknown && proof.Unknown);
   for(int fault=0;fault<3;fault++) {
    var isolated=new PipeCapture();isolated.Receive(first,first.Length);
    int written;Check(!EnvironmentEvidenceSink.TryWriteCounted(new ThrowingDiagnostic(fault),out written));
    Check(written==(fault==0?0:1));isolated.Receive(last,last.Length);
    byte[] retained=new byte[isolated.RetainedCount];Array.Copy(isolated.Retained,retained,retained.Length);
    Check(EnvironmentObservation.Parse(retained).Text==FixedEnvironmentPolicy.Text && isolated.Discarded==0 && !isolated.Unknown);
   }
   for(int i=0;i<9;i++) Check(new ChildCaptureOwner((CaptureCase)i).Scenario==(CaptureCase)i);
   bool refused=false;try { new ChildCaptureOwner((FixedChildEnvironment)null); } catch(ArgumentNullException) { refused=true; }Check(refused);
   Console.WriteLine("managed environment integration PASS");return 0;
  }
  static string B(bool value) { return ChildCaptureOwner.B(value); }
  static string N(long value) { return ChildCaptureOwner.N(value); }
  static string ActualWire(ChildCaptureOwner owner) {
   int count=owner.Channels[0].Capture.RetainedCount;
   // Retain only the allowlisted record, not header or arbitrary unbounded output.
   if(count<40 || count>1544 || owner.Channels[0].Capture.Total!=count) return "null";
   return "\""+Convert.ToBase64String(owner.Channels[0].Capture.Retained,8,count-8)+"\"";
  }
  static string ExpectedDirectory(ChildCaptureOwner owner) {
   return owner.ExpectedWindowsDirectory==null?"null":"\""+Convert.ToBase64String(new System.Text.UnicodeEncoding(false,false,true).GetBytes(owner.ExpectedWindowsDirectory))+"\"";
  }
  static string Report(ChildCaptureOwner owner,int index,bool passed,bool parent,bool restored,bool observed) {
   return "{\"kind\":\"native_environment_case\",\"case\":\""+(EnvironmentObservationFault)index+"\",\"status\":\""+(passed?"PASS":"FAIL")+
    "\",\"observation_base64\":"+ActualWire(owner)+",\"expected_directory_base64\":"+ExpectedDirectory(owner)+",\"overall\":\""+(owner.Unknown?"UNKNOWN":"OBSERVED")+"\",\"create_state\":\""+owner.CreateState+"\",\"created\":"+B(owner.Created)+
    ",\"exit_observed\":"+B(owner.Proof.ExitObserved)+",\"eof_stdout\":"+B(owner.Proof.StdoutEof)+",\"eof_stderr\":"+B(owner.Proof.StderrEof)+
    ",\"resources_released\":"+B(owner.Released)+",\"retained_owner\":"+B(!owner.Released)+",\"environment_released\":"+B(owner.EnvironmentReleased)+
    ",\"parent_sentinel\":"+B(parent)+",\"restored\":"+B(restored)+",\"observed_fields\":"+B(observed)+",\"one_shot_refused\":"+B(owner.OneShotRefused)+
    ",\"sentinel_probe\":"+B(owner.SentinelProbe)+",\"sentinel_unsignaled\":"+B(owner.SentinelUnsignaled)+",\"create_calls\":"+N(owner.CreateCalls)+
    ",\"stdout_bytes\":"+N(owner.Channels[0].Capture.Total)+",\"stderr_bytes\":"+N(owner.Channels[1].Capture.Total)+",\"fault_site\":"+N(owner.FaultSite)+
    ",\"evidence_bytes_written\":"+N(owner.EvidenceBytesWritten)+",\"fault_at_bytes\":"+N(owner.EnvironmentFaultAtBytes)+",\"exit_code\":"+N(owner.ExitCode)+",\"mutation_authorized\":false}";
  }
  static void AssertCase(ChildCaptureOwner owner,FixedChildEnvironment policy,int index) {
   Check(owner.Created && owner.CreateState==CreateEntryState.ReturnedTrue && owner.CreateCalls==1);
   Check(owner.Proof.Complete && owner.Released && owner.EnvironmentReleased && owner.ExitCode==0);
   Check(owner.Unknown==(index!=0) && owner.SentinelProbe && owner.SentinelUnsignaled);
   Check(owner.Channels[1].Capture.Total==0 && owner.Channels[0].Capture.Discarded==0 && !owner.Channels[0].Capture.Unknown);
   int size=owner.Channels[0].Capture.RetainedCount-8;Check(size>=32 && size<=EnvironmentObservation.MaxRecordBytes);
   byte[] bytes=new byte[size];Array.Copy(owner.Channels[0].Capture.Retained,8,bytes,0,size);
   EnvironmentObservation actual=EnvironmentObservation.Parse(bytes);
   Check(!actual.SentinelPresent && actual.Text==FixedEnvironmentPolicy.Text && actual.EmptyPresent && actual.Empty==String.Empty);
   Check(actual.WindowsDirectory==policy.WindowsDirectory && actual.Windir==policy.WindowsDirectory);
   Check(owner.FaultSite==(index==0?0:index==1?1:3));
   if(index==2) Check(owner.EvidenceBytesWritten==1 && owner.EnvironmentFaultAtBytes>=8 && owner.EnvironmentFaultAtBytes<owner.Channels[0].Capture.Total);
   int calls=owner.CreateCalls,rounds=owner.Rounds;
   try { owner.Run(); } catch(InvalidOperationException) { owner.OneShotRefused=true; }
   Check(owner.OneShotRefused && owner.CreateCalls==calls && owner.Rounds==rounds && owner.Released);
  }
  public static int Main(string[] args) {
   if(args.Length!=0 || Environment.OSVersion.Platform!=PlatformID.Win32NT || IntPtr.Size!=8) return 2;
   int failed=0,completed=0;bool allReleased=true,allRestored=true;
   try {
    FixedChildEnvironment policy=FixedChildEnvironment.CreateForObservation();
    byte[] firstCopy=policy.CopyBytes();byte[] secondCopy=policy.CopyBytes();
    firstCopy[0]^=255;Check(firstCopy[0]!=secondCopy[0] && policy.CopyBytes()[0]==secondCopy[0]);
    bool badFault=false;
    try { new ChildCaptureOwner(policy,(EnvironmentObservationFault)99); } catch(ArgumentOutOfRangeException) { badFault=true; }
    Check(badFault);
    // Fixed array roots all lifetime owners before native launch/setup. Never remove one.
    for(int i=0;i<roots.Length;i++) roots[i]=new ChildCaptureOwner(policy,(EnvironmentObservationFault)i);
    allRestored=false;
    NativeLaunchEnvironmentObservationTests.RunNativeSentinelTests();
    allRestored=true;
    for(int i=0;i<roots.Length;i++) {
     ChildCaptureOwner owner=roots[i];NativeEnvironmentSentinel sentinel=null;
     bool passed=false,parent=false,restored=false,observed=false;
     try {
      sentinel=new NativeEnvironmentSentinel();parent=sentinel.ParentPresent;
      owner.Run();AssertCase(owner,policy,i);observed=true;
     } catch { ++failed; }
     finally {
      try { if(sentinel!=null) { sentinel.Dispose();restored=sentinel.Restored; } } catch { ++failed; }
     }
     passed=observed && parent && restored;
     if(!passed && failed==0) ++failed;
     allReleased=allReleased && owner.Released;allRestored=allRestored && restored;++completed;
     Console.WriteLine(Report(owner,i,passed,parent,restored,observed));
     if(!owner.Released || !restored) break;
    }
   } catch { ++failed; }
   bool success=failed==0 && completed==3 && allReleased && allRestored;
   Console.WriteLine("{\"kind\":\"native_environment_summary\",\"status\":\""+(success?"PASS":"FAIL")+"\",\"cases\":"+N(completed)+",\"failed\":"+N(failed)+
    ",\"all_owners_released\":"+B(allReleased)+",\"sentinel_restored\":"+B(allRestored)+",\"mutation_authorized\":false}");
   GC.KeepAlive(roots);return success?0:1;
  }
 }
}
