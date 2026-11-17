// TEST ONLY. Fixed finite binary writer. No command, environment or executable dispatch.
using System;
using System.Runtime.InteropServices;
namespace PortableVBox {
 internal static class NativeCaptureFixtureChild {
  // Assigned before acquisition and never cleared, including unresolved ownership.
  static SentinelObserver observerRoot;
  [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr GetStdHandle(int value);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool WriteFile(IntPtr handle,byte[] bytes,uint count,out uint written,IntPtr overlapped);
  static void Write(IntPtr handle,byte[] bytes,int count) {
   uint written;
   if(!WriteFile(handle,bytes,(uint)count,out written,IntPtr.Zero) || written!=(uint)count)
    throw new InvalidOperationException("Fixed synchronous write failed");
  }
  static byte Pattern(int offset,int seed) { return (byte)((offset*31+seed)&255); }
  // The real output path uses this bounded sink seam in managed contracts as well.
  // It accepts only the already validated fixed parser result and semantic outcome.
  internal static int EmitObserved(SentinelArguments arguments,SentinelResult result,Action<bool,byte[],int> write) {
   try {
    string mode=arguments.CaseName;
    // No header, body, standard-handle query or sink call for the genuine Empty case.
    if(mode=="Empty") return result==SentinelResult.Excluded?0:94;
    int left=17,right=257,exit=0;
    switch(mode) {
     case "Binary": left=4097;break;
     case "Large": case "CaptureFault": case "EvidenceFault": left=196731;right=204829;break;
     case "Nonzero": exit=23;break;
     case "Exit259": exit=259;break;
    }
    byte[] header=SentinelProtocol.Encode(result);
    write(false,header,header.Length);
    if(mode=="EnvironmentObservation") {
     byte[] record=EnvironmentObservation.ReadCurrent().Encode();
     // Native reads may coalesce: the managed fragmentation test still proves
     // diagnostic failure cannot discard the final observation fragment.
     byte[] first=new byte[12];Array.Copy(record,first,first.Length);write(false,first,first.Length);
     byte[] rest=new byte[record.Length-first.Length];Array.Copy(record,first.Length,rest,0,rest.Length);write(false,rest,rest.Length);
     return 0;
    }
    byte[] buffer=new byte[4096];
    int a=0,b=0;
    while(a<left || b<right) {
     if(a<left) { int n=Math.Min(buffer.Length,left-a); for(int i=0;i<n;i++) buffer[i]=Pattern(a+i,0); write(false,buffer,n); a+=n; }
     if(b<right) { int n=Math.Min(buffer.Length,right-b); for(int i=0;i<n;i++) buffer[i]=Pattern(b+i,71); write(true,buffer,n); b+=n; }
    }
    return exit;
   } catch { return 93; }
  }
  static int Main(string[] args) {
   try {
    SentinelArguments arguments;int rejection;
    if(!SentinelArguments.TryParse(args,out arguments,out rejection)) return rejection;
    observerRoot=new SentinelObserver(arguments);
    SentinelObservation observation=observerRoot.ObserveOnce(new NativeSentinelQueryApi());
    if(arguments.CaseName=="Empty") return EmitObserved(arguments,observation.Result,null);
    IntPtr stdout=GetStdHandle(-11),stderr=GetStdHandle(-12);
    return EmitObserved(arguments,observation.Result,delegate(bool error,byte[] bytes,int count) { Write(error?stderr:stdout,bytes,count); });
   } catch { return 93; }
   finally { GC.KeepAlive(observerRoot); }
  }
 }
}
