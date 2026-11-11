// TEST ONLY. Fixed Windows sentinel calls; no launcher or arbitrary target selection.
using System;
using System.Runtime.InteropServices;
namespace PortableVBox {
 internal interface ISentinelQueryNativeCalls {
  void ClearLastError();
  uint CaptureLastError();
  IntPtr OpenEvent(uint access,bool inherit,string name);
  bool GetHandleInformation(IntPtr handle,out uint flags);
  bool CompareObjectHandles(IntPtr first,IntPtr second);
  bool CloseHandle(IntPtr handle);
 }
 internal interface IFreshSentinelNativeCalls {
  void ClearLastError();
  uint CaptureLastError();
  IntPtr CreateEvent(IntPtr privateDescriptor,bool manualReset,bool initialState,bool inherit,string name);
  bool SetHandleInformation(IntPtr handle,uint mask,uint flags);
  bool CloseHandle(IntPtr handle);
 }
 // Windows 10 / Server 2016 minimum for this test-only comparison API.
 // An unavailable export propagates to the observer as UNKNOWN, never a fallback.
 internal sealed class SentinelNativeCalls : ISentinelQueryNativeCalls,IFreshSentinelNativeCalls {
  [StructLayout(LayoutKind.Sequential)] struct SecurityAttributes {
   internal int Length;
   internal IntPtr Descriptor;
   [MarshalAs(UnmanagedType.Bool)] internal bool Inherit;
  }
  [DllImport("kernel32.dll",ExactSpelling=true,SetLastError=true)] static extern void SetLastError(uint error);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,ExactSpelling=true,SetLastError=true)]
  static extern IntPtr OpenEventW(uint access,[MarshalAs(UnmanagedType.Bool)] bool inherit,string name);
  [DllImport("kernel32.dll",ExactSpelling=true,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool GetHandleInformation(IntPtr handle,out uint flags);
  [DllImport("Kernelbase.dll",ExactSpelling=true,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool CompareObjectHandles(IntPtr first,IntPtr second);
  [DllImport("kernel32.dll",ExactSpelling=true,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,ExactSpelling=true,SetLastError=true)]
  static extern IntPtr CreateEventW(ref SecurityAttributes security,[MarshalAs(UnmanagedType.Bool)] bool manualReset,[MarshalAs(UnmanagedType.Bool)] bool initialState,string name);
  [DllImport("kernel32.dll",ExactSpelling=true,SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool SetHandleInformation(IntPtr handle,uint mask,uint flags);
  public void ClearLastError() { SetLastError(0); }
  public uint CaptureLastError() { return unchecked((uint)Marshal.GetLastWin32Error()); }
  public IntPtr OpenEvent(uint access,bool inherit,string name) { return OpenEventW(access,inherit,name); }
  bool ISentinelQueryNativeCalls.GetHandleInformation(IntPtr handle,out uint flags) { return GetHandleInformation(handle,out flags); }
  bool ISentinelQueryNativeCalls.CompareObjectHandles(IntPtr first,IntPtr second) { return CompareObjectHandles(first,second); }
  bool ISentinelQueryNativeCalls.CloseHandle(IntPtr handle) { return CloseHandle(handle); }
  bool IFreshSentinelNativeCalls.CloseHandle(IntPtr handle) { return CloseHandle(handle); }
  bool IFreshSentinelNativeCalls.SetHandleInformation(IntPtr handle,uint mask,uint flags) { return SetHandleInformation(handle,mask,flags); }
  public IntPtr CreateEvent(IntPtr privateDescriptor,bool manualReset,bool initialState,bool inherit,string name) {
   var security=new SecurityAttributes();security.Length=Marshal.SizeOf(typeof(SecurityAttributes));
   security.Descriptor=privateDescriptor;security.Inherit=inherit;
   return CreateEventW(ref security,manualReset,initialState,name);
  }
 }
 internal sealed class NativeSentinelQueryApi : ISentinelQueryApi {
  readonly ISentinelQueryNativeCalls calls;
  IntPtr ownedReference;
  bool openEntered,closeEntered;
  internal NativeSentinelQueryApi():this(new SentinelNativeCalls()) { }
  internal NativeSentinelQueryApi(ISentinelQueryNativeCalls calls) {
   if(calls==null) throw new ArgumentNullException("calls");this.calls=calls;
  }
  public IntPtr OpenReference(string name,out uint error) {
   const string prefix="Local\\pvbox-fixed-sentinel-";
   if(name==null || !name.StartsWith(prefix,StringComparison.Ordinal) || !SentinelProtocol.ValidToken(name.Substring(prefix.Length)))
    throw new ArgumentException("Fixed sentinel name required","name");
   if(openEntered) throw new InvalidOperationException("Reference open is one-shot");openEntered=true;
   error=0;
   calls.ClearLastError();
   ownedReference=calls.OpenEvent(0x00100000,false,name);
   if(ownedReference==IntPtr.Zero) error=calls.CaptureLastError();
   return ownedReference;
  }
  public bool QueryHandle(IntPtr handle,out uint flags,out uint error) {
   error=0;
   calls.ClearLastError();
   bool result=calls.GetHandleInformation(handle,out flags);
   if(!result) error=calls.CaptureLastError();
   return result;
  }
  public bool CompareHandles(IntPtr first,IntPtr second,out uint error) {
   error=0;
   calls.ClearLastError();
   bool result=calls.CompareObjectHandles(first,second);
   if(!result) error=calls.CaptureLastError();
   return result;
  }
  public bool CloseReference(IntPtr reference,out uint error) {
   if(reference==IntPtr.Zero || reference!=ownedReference || closeEntered)
    throw new InvalidOperationException("Only the owned reference may close once");
   closeEntered=true;error=0;
   calls.ClearLastError();
   bool result=calls.CloseHandle(reference);
   if(!result) error=calls.CaptureLastError();
   if(result) ownedReference=IntPtr.Zero;
   return result;
  }
 }
}
