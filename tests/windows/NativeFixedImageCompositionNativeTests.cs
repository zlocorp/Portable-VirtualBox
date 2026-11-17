// TEST ONLY. Closed fixed sibling Binary composition; no external execution inputs.
using System;
namespace PortableVBox {
 public static class NativeFixedImageCompositionNativeTests {
  static FixedFixtureImage image;
  static ChildCaptureOwner root;
  static void Check(bool value) { if(!value)throw new InvalidOperationException("Composed fixed-image assertion failed"); }
  static bool Denied(FixedImageProbeObservation p) { return p!=null && p.OpenState=="returned-failure" && p.OpenError==32 && p.CloseState=="not-opened"; }
  static void AssertOneShot() {
   if(root.OneShotRefused)return; // Full AssertCase already checked the second Run on success.
   int rounds=root.Rounds,creates=root.CreateCalls;bool released=root.Released;
   try { root.Run(); } catch(InvalidOperationException) { root.OneShotRefused=true; }
   Check(root.OneShotRefused && root.Rounds==rounds && root.CreateCalls==creates && root.Released==released);
  }
  static void AssertObservation(string scenario) {
   var o=image.Observation;
   Check(root.Released && image.Released);
   if(scenario=="matching-image") {
    // This is the unchanged nine-case suite's full Binary assertion, never a subset.
    NativeChildCaptureNativeTests.AssertCase(root);
    var q=root.ProcessImageObservation;var e=root.ExitObservation;
    Check(root.OriginalHandlesObservation.State=="valid" && q.Entered && q.Returned==true && q.Error==null && q.PathState=="valid" && q.Agree==true && q.ReturnedLength>0 && q.ReturnedLength<32768);
    Check(q.Path!=null && q.ReturnedLength==q.Path.Length && FixedImagePath.Agree(o.HeldPath,q.Path));
    Check(e.WaitEntered && e.WaitReturn==0 && e.WaitError==null && e.CodeEntered && e.CodeReturn==true && e.CodeError==null && e.Code==0);
    Check(o.Refusal=="none" && o.OpenState=="returned-success" && o.OpenError==null && o.ActualSize==image.Expected.Length && o.ActualSha256==image.Expected.Sha256 && o.BytesHashed==image.Expected.Length && o.ReadState=="complete" && o.EofRequestBytes==1 && o.EofReturnBytes==0);
    Check(o.VolumeSerial!=null && o.FileId!=null && o.HeldPath!=null && o.CloseState=="returned-success" && Denied(image.WriteProbeObservation) && Denied(image.DeleteProbeObservation));
   } else {
    Check(root.CreateCalls==0 && root.CreateState==CreateEntryState.NotEntered && !root.Created && root.OriginalHandlesObservation.State=="not-observed" && !root.ProcessImageObservation.Entered && root.WaitCalls==0 && root.ExitCodeReads==0);
    Check(Array.IndexOf(root.CompositionTrace,"PrepareTransport")<0 && Array.IndexOf(root.CompositionTrace,"Launch")<0 && image.WriteProbeObservation==null && image.DeleteProbeObservation==null);
    if(scenario=="digest-mismatch")Check(o.Refusal==scenario && o.ActualSize==image.Expected.Length && o.ReadState=="complete" && o.ActualSha256!=null && o.ActualSha256!=image.Expected.Sha256 && o.BytesHashed==image.Expected.Length && o.EofRequestBytes==1 && o.EofReturnBytes==0 && o.CloseState=="returned-success");
    else if(scenario=="size-mismatch")Check(o.Refusal==scenario && o.ActualSize.HasValue && o.ActualSize!=image.Expected.Length && o.ReadState=="not-entered" && o.ActualSha256==null && o.BytesHashed==0 && o.CloseState=="returned-success");
    else Check(o.Refusal=="missing-image" && o.OpenState=="returned-failure" && o.OpenError==2 && o.ActualSize==null && o.ActualSha256==null && o.ReadState=="not-entered" && o.BytesHashed==0 && o.CloseState=="not-opened");
   }
  }
  public static int Main() {
   if(Environment.GetCommandLineArgs().Length!=1 || Environment.OSVersion.Platform!=PlatformID.Win32NT || IntPtr.Size!=8)return 3;
   string scenario=FixedFixtureCase.Name;
   if(scenario!="matching-image" && scenario!="digest-mismatch" && scenario!="size-mismatch" && scenario!="missing-image")return 3;
   image=FixedFixtureImage.CreateForObservation();root=new ChildCaptureOwner(image);
   bool passed=false;
   try { root.Run();AssertObservation(scenario);AssertOneShot();passed=true; }
   catch { try { AssertOneShot(); } catch { } }
   // No transferred-image cleanup here: Run/Release alone own all lifecycle gates.
   var snapshot=root.CompositionSnapshot(scenario,passed);
   Console.WriteLine(snapshot.Json);
   bool released=root.Released && image.Released;GC.KeepAlive(root);GC.KeepAlive(image);
   return !released?2:passed?0:1;
  }
 }
}
