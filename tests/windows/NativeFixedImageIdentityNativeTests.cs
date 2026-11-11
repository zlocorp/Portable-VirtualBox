// TEST ONLY: one compile-time fixed case, fixed sibling, no fixture-child launch.
using System;
namespace PortableVBox {
 public static class NativeFixedImageIdentityNativeTests {
  static FixedFixtureImage root;
  public static int Main(string[] args) {
   if(args.Length!=0 || Environment.OSVersion.Platform!=PlatformID.Win32NT || IntPtr.Size!=8)return 3;
   string scenario=FixedFixtureCase.Name;
   if(scenario!="matching-image" && scenario!="digest-mismatch" && scenario!="size-mismatch" && scenario!="missing-image")return 3;
   bool observed=false,passed=false;
   root=FixedFixtureImage.CreateForObservation();
   try {
    root.PrepareOnce();var o=root.Observation;
    bool oneShot=false;try { root.PrepareOnce(); } catch(InvalidOperationException) { oneShot=true; }
    if(scenario=="matching-image")observed=oneShot && root.Ready && root.ObserveSharing();
    else if(scenario=="digest-mismatch")observed=oneShot && o.Refusal=="digest-mismatch" && o.ActualSize==root.Expected.Length && o.ActualSha256!=null && o.ActualSha256!=root.Expected.Sha256 && o.ReadState=="complete" && o.BytesHashed==root.Expected.Length && o.EofRequestBytes==1 && o.EofReturnBytes==0;
    else if(scenario=="size-mismatch")observed=oneShot && o.Refusal=="size-mismatch" && o.ActualSize!=null && o.ActualSize!=root.Expected.Length && o.ReadState=="not-entered" && o.ActualSha256==null && o.BytesHashed==0;
    else observed=oneShot && o.Refusal=="missing-image" && o.OpenState=="returned-failure" && o.OpenError==2 && o.ActualSize==null && o.ActualSha256==null && o.ReadState=="not-entered" && o.BytesHashed==0;
   } catch { observed=false; }
   finally { try { passed=root.TryRelease() && observed; } catch { passed=false; } }
   Console.WriteLine(root.Report(scenario,passed));
   bool released=root.Released;GC.KeepAlive(root);
   return !released?2:passed?0:1;
  }
 }
}
