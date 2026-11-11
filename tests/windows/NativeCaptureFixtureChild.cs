// TEST ONLY. Fixed finite binary writer. No command, environment or executable dispatch.
using System;
using System.Globalization;
using System.Runtime.InteropServices;
namespace PortableVBox {
 internal static class NativeCaptureFixtureChild {
  [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr GetStdHandle(int value);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool WriteFile(IntPtr handle,byte[] bytes,uint count,out uint written,IntPtr overlapped);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] static extern bool SetEvent(IntPtr handle);
  static void Write(IntPtr handle,byte[] bytes,int count) {
   uint written;
   if(!WriteFile(handle,bytes,(uint)count,out written,IntPtr.Zero) || written!=(uint)count)
    throw new InvalidOperationException("Fixed synchronous write failed");
  }
  static byte Pattern(int offset,int seed) { return (byte)((offset*31+seed)&255); }
  static int Main(string[] args) {
   try {
    if(args.Length!=2) return 90;
    string mode=args[0];
    int left=17,right=257,exit=0;
    switch(mode) {
     case "Empty": left=0;right=0;break;
     case "Binary": left=4097;right=257;break;
     case "Large": case "CaptureFault": case "EvidenceFault": left=196731;right=204829;break;
     case "Nonzero": exit=23;break;
     case "Exit259": exit=259;break;
     case "PostCreateFault": case "WithheldEof": case "EnvironmentObservation": break;
     default: return 91;
    }
    long sentinel;
    if(!Int64.TryParse(args[1],NumberStyles.None,CultureInfo.InvariantCulture,out sentinel) || sentinel<=0) return 92;
    bool signaled=SetEvent(new IntPtr(sentinel));
    int error=signaled?0:Marshal.GetLastWin32Error();
    // Empty proves probe completion through its dedicated exit branch, with no writes.
    if(mode=="Empty") return !signaled && error==6?0:94;
    byte[] header={80,86,67,49,(byte)(signaled?1:0),(byte)error,(byte)(error>>8),165};
    IntPtr stdout=GetStdHandle(-11),stderr=GetStdHandle(-12);
    Write(stdout,header,header.Length);
    if(mode=="EnvironmentObservation") {
     byte[] record=EnvironmentObservation.ReadCurrent().Encode();
     // Native reads may coalesce: a separate deterministic managed fragmentation test
     // proves diagnostic failure cannot discard the final observation fragment.
     byte[] first=new byte[12];Array.Copy(record,first,first.Length);Write(stdout,first,first.Length);
     byte[] rest=new byte[record.Length-first.Length];Array.Copy(record,first.Length,rest,0,rest.Length);Write(stdout,rest,rest.Length);
     return 0;
    }
    byte[] buffer=new byte[4096];
    int a=0,b=0;
    while(a<left || b<right) {
     if(a<left) { int n=Math.Min(buffer.Length,left-a); for(int i=0;i<n;i++) buffer[i]=Pattern(a+i,0); Write(stdout,buffer,n); a+=n; }
     if(b<right) { int n=Math.Min(buffer.Length,right-b); for(int i=0;i<n;i++) buffer[i]=Pattern(b+i,71); Write(stderr,buffer,n); b+=n; }
    }
    return exit;
   } catch { return 93; }
  }
 }
}
