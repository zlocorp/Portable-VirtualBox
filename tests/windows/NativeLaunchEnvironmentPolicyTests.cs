// TEST ONLY. Pure decisions; never native launch or memory calls.
using System;
using System.Text;
namespace PortableVBox {
 public static class NativeLaunchEnvironmentPolicyTests {
  static int checks;
  static void Check(bool value,string name) { ++checks;if(!value) throw new InvalidOperationException(name); }
  static void Reject(Action action,string name) { bool rejected=false;try { action(); } catch(ArgumentException) { rejected=true; } Check(rejected,name); }
  public static int RunManaged() {
   checks=0;
   Check(FixedEnvironmentPolicy.ValidateWindowsDirectory(10,@"C:\Windows")==@"C:\Windows","valid directory preserved");
   Check(FixedEnvironmentPolicy.ValidateWindowsDirectory(3,@"z:\")==@"z:\","drive root supported");
   string unicode=@"D:\Окно\"+"\U0001F642";
   Check(FixedEnvironmentPolicy.ValidateWindowsDirectory((uint)unicode.Length,unicode)==unicode,"Unicode directory preserved");
   foreach(string invalid in new string[]{null,"",@"C:",@"\\server\share",@"\\?\C:\Windows",@"C:/Windows",@"1:\Windows",@"C:\a\",@"C:\a\\b",@"C:\.",@"C:\..",@"C:\a.",@"C:\a ",@"C:\a:b",@"C:\a|b",@"C:\a*b",@"C:\a?b",@"C:\a<b",@"C:\a>b","C:\\a\"b","C:\\a\0b","C:\\a\nb","C:\\\ud800","C:\\\udc00"}) {
    string value=invalid;Reject(delegate { FixedEnvironmentPolicy.ValidateWindowsDirectory(value==null?0:(uint)value.Length,value); },"invalid directory rejected");
   }
   foreach(uint length in new uint[]{0,1,2,9,11,260,UInt32.MaxValue}) { uint result=length;Reject(delegate {FixedEnvironmentPolicy.ValidateWindowsDirectory(result,@"C:\Windows");},"native length rejected"); }
   string max=@"C:\"+new string('x',256);Check(FixedEnvironmentPolicy.ValidateWindowsDirectory(259,max)==max,"259 bound accepted");
   Reject(delegate { FixedEnvironmentPolicy.ValidateWindowsDirectory(260,max+"x"); },"260 bound rejected");
   byte[] block=FixedEnvironmentPolicy.EncodeDirectory(@"C:\Windows");
   string expected="PVBOX_FIXTURE_EMPTY=\0PVBOX_FIXTURE_TEXT=Привет = fixture \U0001F642\0SystemRoot=C:\\Windows\0WINDIR=C:\\Windows\0\0";
   Check(Encoding.Unicode.GetString(block)==expected,"exact four fixed entries");
   block[0]=0;Check(Encoding.Unicode.GetString(FixedEnvironmentPolicy.EncodeDirectory(@"C:\Windows"))==expected,"independent policy bytes");
   var fresh=new EnvironmentAllocationProof();
   Check(fresh.CanRelease(CreateEntryState.NotEntered) && fresh.Released,"no allocation is resolved");
   fresh.BeginPreparation();Reject(delegate {fresh.BeginPreparation();},"preparation one shot");
   fresh.BeforeAllocate();Check(fresh.AllocationUnknown && !fresh.CanRelease(CreateEntryState.NotEntered),"unreturned allocation retained");
   Reject(delegate {fresh.BeforeAllocate();},"allocation not retried");
   fresh.AllocateReturned();Check(!fresh.AllocationUnknown && !fresh.Released,"allocation return recorded");
   Check(fresh.CanRelease(CreateEntryState.NotEntered),"pre-create failure can free");
   Check(fresh.CanRelease(CreateEntryState.ReturnedFalse),"known FALSE can free");
   Check(fresh.CanRelease(CreateEntryState.ReturnedTrue),"known TRUE permits environment only");
   Check(!fresh.CanRelease(CreateEntryState.EnteredReturnUnknown),"unknown create retained");
   Check(!fresh.CanRelease((CreateEntryState)77),"invalid create state refused");
   fresh.BeforeFree(CreateEntryState.ReturnedFalse);Check(fresh.ReleaseUncertain && !fresh.CanRelease(CreateEntryState.ReturnedFalse),"free without return retained");
   Reject(delegate {fresh.BeforeFree(CreateEntryState.ReturnedFalse);},"free never retried");
   fresh.FreeReturned();Check(fresh.Released && !fresh.ReleaseUncertain,"known free resolved");
   Reject(delegate {fresh.FreeReturned();},"free completion one shot");
   var rejected=new EnvironmentAllocationProof();rejected.BeginPreparation();Check(rejected.CanRelease(CreateEntryState.NotEntered) && rejected.Released,"preparation rejection no native allocation");
   Reject(delegate {rejected.AllocateReturned();},"cannot synthesize allocation return before entry");
   var unknown=new EnvironmentAllocationProof();unknown.BeginPreparation();unknown.BeforeAllocate();unknown.AllocateReturned();
   Reject(delegate {unknown.BeforeFree(CreateEntryState.EnteredReturnUnknown);},"unknown create cannot free");
   var closedBeforePreparation=new EnvironmentAllocation();
   Check(closedBeforePreparation.TryRelease(CreateEntryState.NotEntered),"unused memory release resolves");
   string closedMessage="";
   try {closedBeforePreparation.Prepare(null);} catch(ArgumentException error) {closedMessage=error.Message;}
   Check(closedMessage=="Released storage cannot be prepared","release forbids future preparation before validation");
   var noMemory=new EnvironmentAllocation();
   Check(noMemory.Released && noMemory.Pointer==IntPtr.Zero,"fresh native owner has no memory");
   Reject(delegate {noMemory.Prepare(null);},"null rejected before native allocation");
   Check(!noMemory.AllocationUnknown && noMemory.Released,"preparation validation never enters native allocation");
   Reject(delegate {noMemory.Prepare(new byte[4]);},"failed preparation not retried");
   Check(noMemory.TryRelease(CreateEntryState.NotEntered),"pre-entry rejection releases no native memory");
   Check(!noMemory.TryRelease(CreateEntryState.NotEntered),"release attempt one shot");
   foreach(byte[] invalid in new byte[][] {new byte[0],new byte[3],new byte[5],new byte[32770],new byte[]{0,0,1,0}}) {
    var storage=new EnvironmentAllocation();byte[] input=invalid;
    Reject(delegate {storage.Prepare(input);},"invalid block rejected before allocation");
    Check(storage.Released && !storage.AllocationUnknown,"invalid block has no native side effects");
   }
   Console.WriteLine("managed fixed-environment policy contracts PASS ("+checks+")");return 0;
  }
  public static int Main() { return RunManaged(); }
 }
}
