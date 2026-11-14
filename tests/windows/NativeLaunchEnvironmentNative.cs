// TEST ONLY. Closed environment policy and one-shot retained unmanaged storage.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
namespace PortableVBox {
 internal enum CreateEntryState { NotEntered,EnteredReturnUnknown,ReturnedFalse,ReturnedTrue }
 internal enum EnvironmentCallState { NotEntered,EnteredReturnUnknown,Returned }
 internal static class FixedEnvironmentPolicy {
  internal const string Text="Привет = fixture \U0001F642";
  internal static string ValidateWindowsDirectory(uint returned,string value) {
   if(value==null || returned<3 || returned>=260 || returned!=(uint)value.Length ||
    !Letter(value[0]) || value[1]!=':' || value[2]!='\\') throw new ArgumentException("Unsupported OS Windows directory");
   for(int i=0;i<value.Length;i++) {
    char c=value[i];
    if(Char.IsControl(c) || c=='/' || (i>2 && "<>:\"|?*".IndexOf(c)>=0)) throw new ArgumentException("Unsupported directory character");
    if(Char.IsHighSurrogate(c)) { if(++i>=value.Length || !Char.IsLowSurrogate(value[i])) throw new ArgumentException("Invalid directory UTF-16"); }
    else if(Char.IsLowSurrogate(c)) throw new ArgumentException("Invalid directory UTF-16");
   }
   if(value.Length>3) foreach(string component in value.Substring(3).Split('\\')) {
    if(component.Length==0 || component=="." || component==".." || component[component.Length-1]==' ' || component[component.Length-1]=='.')
     throw new ArgumentException("Unsupported directory component");
   }
   return value;
  }
  static bool Letter(char c) { return (c>='A' && c<='Z') || (c>='a' && c<='z'); }
  // Pure serializer utility cannot construct a launch policy or enter native creation.
  internal static byte[] EncodeDirectory(string directory) {
   ValidateWindowsDirectory(directory==null?0:(uint)directory.Length,directory);
   return EnvironmentBlockCodec.Encode(new KeyValuePair<string,string>[] {
    new KeyValuePair<string,string>("SystemRoot",directory),new KeyValuePair<string,string>("WINDIR",directory),
    new KeyValuePair<string,string>("PVBOX_FIXTURE_TEXT",Text),new KeyValuePair<string,string>("PVBOX_FIXTURE_EMPTY",String.Empty)
   });
  }
 }
 internal sealed class FixedChildEnvironment {
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,ExactSpelling=true,SetLastError=true)]
  static extern uint GetSystemWindowsDirectoryW(StringBuilder buffer,uint size);
  readonly byte[] bytes;
  readonly string directory;
  FixedChildEnvironment(string verifiedDirectory) { directory=verifiedDirectory;bytes=FixedEnvironmentPolicy.EncodeDirectory(verifiedDirectory); }
  internal static FixedChildEnvironment CreateForObservation() {
   var buffer=new StringBuilder(260);
   uint returned=GetSystemWindowsDirectoryW(buffer,260);
   return new FixedChildEnvironment(FixedEnvironmentPolicy.ValidateWindowsDirectory(returned,buffer.ToString()));
  }
  internal string WindowsDirectory { get { return directory; } }
  internal byte[] CopyBytes() { return (byte[])bytes.Clone(); }
 }
 // Pure bookkeeping. The real memory owner never exposes this instance to callers.
 internal sealed class EnvironmentAllocationProof {
  bool prepared;
  EnvironmentCallState allocation,free;
  internal bool AllocationUnknown { get { return allocation==EnvironmentCallState.EnteredReturnUnknown; } }
  internal bool ReleaseUncertain { get { return free==EnvironmentCallState.EnteredReturnUnknown; } }
  internal bool Released { get { return allocation==EnvironmentCallState.NotEntered || free==EnvironmentCallState.Returned; } }
  internal void BeginPreparation() { if(prepared) throw new ArgumentException("Preparation already attempted");prepared=true; }
  internal void BeforeAllocate() {
   if(!prepared || allocation!=EnvironmentCallState.NotEntered || free!=EnvironmentCallState.NotEntered) throw new ArgumentException("Allocation entry refused");
   allocation=EnvironmentCallState.EnteredReturnUnknown;
  }
  internal void AllocateReturned() {
   if(allocation!=EnvironmentCallState.EnteredReturnUnknown) throw new ArgumentException("No allocation awaiting return");
   allocation=EnvironmentCallState.Returned;
  }
  internal bool CanRelease(CreateEntryState state) {
   if(state!=CreateEntryState.NotEntered && state!=CreateEntryState.ReturnedFalse && state!=CreateEntryState.ReturnedTrue) return false;
   return allocation!=EnvironmentCallState.EnteredReturnUnknown && free==EnvironmentCallState.NotEntered;
  }
  internal void BeforeFree(CreateEntryState state) {
   if(!CanRelease(state) || allocation!=EnvironmentCallState.Returned) throw new ArgumentException("Free entry refused");
   free=EnvironmentCallState.EnteredReturnUnknown;
  }
  internal void FreeReturned() {
   if(free!=EnvironmentCallState.EnteredReturnUnknown) throw new ArgumentException("No free awaiting return");
   free=EnvironmentCallState.Returned;
  }
 }
 internal sealed class EnvironmentAllocation {
  readonly EnvironmentAllocationProof proof=new EnvironmentAllocationProof();
  IntPtr pointer;
  bool releaseAttempted;
  internal IntPtr Pointer { get { return pointer; } }
  internal bool AllocationUnknown { get { return proof.AllocationUnknown; } }
  internal bool ReleaseUncertain { get { return proof.ReleaseUncertain; } }
  internal bool Released { get { return proof.Released && pointer==IntPtr.Zero; } }
  internal void Prepare(byte[] bytes) {
   if(releaseAttempted) throw new ArgumentException("Released storage cannot be prepared");
   proof.BeginPreparation();
   if(bytes==null || bytes.Length<4 || bytes.Length>32768 || (bytes.Length&1)!=0 ||
    bytes[bytes.Length-1]!=0 || bytes[bytes.Length-2]!=0 || bytes[bytes.Length-3]!=0 || bytes[bytes.Length-4]!=0)
    throw new ArgumentException("Invalid bounded prepared environment");
   // No allocation or potentially throwing work after entry except the recorded call.
   proof.BeforeAllocate();
   pointer=Marshal.AllocHGlobal(bytes.Length);
   proof.AllocateReturned();
   if(pointer==IntPtr.Zero) throw new InvalidOperationException("Environment allocation returned null");
   Marshal.Copy(bytes,0,pointer,bytes.Length);
  }
  internal bool TryRelease(CreateEntryState state) {
   if(releaseAttempted || !proof.CanRelease(state)) return false;
   releaseAttempted=true;
   if(pointer==IntPtr.Zero) return proof.Released;
   proof.BeforeFree(state);
   Marshal.FreeHGlobal(pointer);
   proof.FreeReturned();
   pointer=IntPtr.Zero;
   return true;
  }
 }
}
