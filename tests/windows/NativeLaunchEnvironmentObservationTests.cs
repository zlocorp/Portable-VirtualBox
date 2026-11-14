// TEST ONLY: pure observation contracts; native checks run only on hosted Windows.
using System;
using System.Text;
using System.IO;
namespace PortableVBox {
 public static class NativeLaunchEnvironmentObservationTests {
  static void Check(bool condition,string name) { if(!condition) throw new Exception("ASSERT: "+name); }
  static void Reject(Action action,string name) { bool rejected=false;try { action(); } catch(ArgumentException) { rejected=true; } Check(rejected,name); }
  static EnvironmentObservation Block(string block) { return EnvironmentObservation.FromBlock(delegate(int i) { if(i>=block.Length) throw new ArgumentException("unterminated");return block[i]; }); }
  public static int RunNativeSentinelTests() {
   string original=EnvironmentObservation.ReadCurrent().Sentinel;
   try {
    foreach(string initial in new string[] {null,"","prior Привет \U0001F642 = value"}) {
     for(int fault=0;fault<2;fault++) {
      NativeEnvironmentSentinel.Set(initial);
      Check(String.Equals(EnvironmentObservation.ReadCurrent().Sentinel,initial,StringComparison.Ordinal),"native sentinel initial state");
      NativeEnvironmentSentinel scope=null;bool sawFault=false;
      try { scope=new NativeEnvironmentSentinel();Check(scope.ParentPresent,"native parent sentinel");if(fault==1)throw new IOException("controlled sentinel body fault"); }
      catch(IOException) { sawFault=true; }
      finally { if(scope!=null)scope.Dispose(); }
      Check(scope!=null && scope.Restored && sawFault==(fault==1),"native scope restored after normal/fault body");
      Check(String.Equals(EnvironmentObservation.ReadCurrent().Sentinel,initial,StringComparison.Ordinal),"independent native exact state verification");
     }
    }
   } finally {
    NativeEnvironmentSentinel.Set(original);
    Check(String.Equals(EnvironmentObservation.ReadCurrent().Sentinel,original,StringComparison.Ordinal),"native matrix restored original state");
   }
   return 0;
  }
  public static int RunManaged() {
   byte[] raw=Encoding.Unicode.GetBytes("SystemRoot=C:\\Windows\0WINDIR=C:\\Windows\0PVBOX_FIXTURE_TEXT=Привет = fixture \U0001F642\0PVBOX_FIXTURE_EMPTY=\0\0");
   EnvironmentObservation observed=EnvironmentObservation.FromBlock(delegate(int index) { return (char)(raw[index*2]|raw[index*2+1]<<8); });
   Check(observed!=null,"complete native block produces observation");
   Check(observed.EmptyPresent && observed.Empty=="" && !observed.SentinelPresent,"empty presence distinct from absence");
   Check(observed.Text=="Привет = fixture \U0001F642" && observed.WindowsDirectory=="C:\\Windows" && observed.Windir=="C:\\Windows","actual values");
   byte[] record=observed.Encode();
   Check(record.Length<=16384 && record[0]==80 && record[1]==86 && record[2]==69 && record[3]==49 && record[6]==30,"record layout");
   EnvironmentObservation parsed=EnvironmentObservation.Parse(record);
   Check(parsed.Text==observed.Text && parsed.EmptyPresent && !parsed.SentinelPresent,"record round trip");
   for(int length=0;length<record.Length;length++) { byte[] torn=new byte[length];Array.Copy(record,torn,length);Reject(delegate { EnvironmentObservation.Parse(torn); },"truncated record"); }
   byte[] extra=new byte[record.Length+1];Array.Copy(record,extra,record.Length);Reject(delegate { EnvironmentObservation.Parse(extra); },"trailing byte");
   foreach(int at in new int[] {0,4,7,8,12}) { byte[] bad=(byte[])record.Clone();bad[at]=255;Reject(delegate { EnvironmentObservation.Parse(bad); },"invalid header/length"); }
   byte[] odd=(byte[])record.Clone();odd[16]=1;Reject(delegate { EnvironmentObservation.Parse(odd); },"odd UTF16 length");
   byte[] nul=(byte[])record.Clone();nul[20]=0;nul[21]=0;Reject(delegate { EnvironmentObservation.Parse(nul); },"embedded NUL");
   byte[] surrogate=(byte[])record.Clone();surrogate[20]=0;surrogate[21]=216;Reject(delegate { EnvironmentObservation.Parse(surrogate); },"unpaired UTF16");
   EnvironmentObservation hidden=Block("=C:=C:\\work\0X=value=equals\0\0");Check(!hidden.SentinelPresent && !hidden.EmptyPresent,"valid absent observations after complete scan");
   foreach(string bad in new string[] {"X=1\0x=2\0\0","broken\0\0","=bad=value\0\0","X=\ud800\0\0","X=1\0","\0"}) Reject(delegate { Block(bad); },"malformed block");
   Reject(delegate { Block("X="+new string('x',8190)+"\0\0"); },"entry bound including NUL");
   StringBuilder many=new StringBuilder();for(int i=0;i<513;i++)many.Append("K"+i+"=\0");many.Append('\0');Reject(delegate { Block(many.ToString()); },"entry count bound");
   Reject(delegate { EnvironmentObservation.FromBlock(delegate(int i) { return i%8192==8191?'\0':(i%8192==1?'=':'x'); }); },"unterminated block bound");
   Check(!Block("\0\0").SentinelPresent,"empty complete block accepted");
   string exactBlock="A="+new string('a',8189)+"\0B="+new string('b',8189)+"\0C="+new string('c',8189)+"\0D="+new string('d',8188)+"\0\0";
   Check(exactBlock.Length==32768 && !Block(exactBlock).SentinelPresent,"exact block and entry bounds accepted");
   Reject(delegate { Block(exactBlock.Insert(exactBlock.Length-2,"d")); },"block limit plus one rejected");
   StringBuilder exactEntries=new StringBuilder();for(int i=0;i<512;i++)exactEntries.Append("K"+i+"=\0");exactEntries.Append('\0');Check(!Block(exactEntries.ToString()).SentinelPresent,"exact entry count accepted");
   Reject(delegate { Block("=C:=first\0=c:=duplicate\0\0"); },"hidden drive names participate in duplicate checks");
   string fullRecordBlock=EnvironmentObservation.SentinelName+"="+new string('s',4096)+"\0PVBOX_FIXTURE_TEXT="+new string('t',4080)+"\0\0";
   byte[] fullRecord=Block(fullRecordBlock).Encode();Check(fullRecord.Length==16384 && EnvironmentObservation.Parse(fullRecord).Sentinel.Length==4096,"exact record/field bounds accepted");
   Reject(delegate { Block(fullRecordBlock.Insert(fullRecordBlock.Length-2,"t")).Encode(); },"record limit plus UTF16 unit rejected");
   Reject(delegate { Block(EnvironmentObservation.SentinelName+"="+new string('s',4097)+"\0\0"); },"reported field limit rejected");
   byte[] inconsistent=(byte[])record.Clone();inconsistent[6]=28;Reject(delegate { EnvironmentObservation.Parse(inconsistent); },"absent field cannot carry bytes");
   int frees=0;IntPtr seen=IntPtr.Zero;
   EnvironmentObservation owned=EnvironmentObservation.ReadOwnedBlock(new IntPtr(42),delegate(int i) { return '\0'; },delegate(IntPtr original) { ++frees;seen=original;return true; });
   Check(owned!=null && frees==1 && seen==new IntPtr(42),"free exact original once after scan");
   Reject(delegate { EnvironmentObservation.ReadOwnedBlock(IntPtr.Zero,delegate(int i) { throw new Exception("must not scan null"); },delegate(IntPtr original) { throw new Exception("must not free null"); }); },"null native observation is invalid");
   frees=0;Reject(delegate { EnvironmentObservation.ReadOwnedBlock(new IntPtr(42),delegate(int i) { return i==0?'x':'\0'; },delegate(IntPtr original) { ++frees;return true; }); },"malformed scan invalid after free");Check(frees==1,"free after failed scan");
   frees=0;bool freeFailed=false;try { EnvironmentObservation.ReadOwnedBlock(new IntPtr(42),delegate(int i) { return '\0'; },delegate(IntPtr original) { ++frees;return false; }); } catch(InvalidOperationException) { freeFailed=true; }Check(freeFailed && frees==1,"failed free invalidates absence without retry");
   frees=0;bool freeUnknown=false;try { EnvironmentObservation.ReadOwnedBlock(new IntPtr(42),delegate(int i) { return '\0'; },delegate(IntPtr original) { ++frees;throw new IOException("unavailable free return"); }); } catch(IOException) { freeUnknown=true; }Check(freeUnknown && frees==1,"unknown free never retried");
   Console.WriteLine("PASS environment observation managed contracts");return 0;
  }
 }
}
