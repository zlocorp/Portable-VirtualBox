// Managed-only tests of the actual production environment, reader and ownership gate.
// No native process, service, driver or Windows call is made.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
namespace PortableVBox {
 public static class FixedEffectWorkerManagedTests {
  static readonly BindingFlags Hidden=BindingFlags.NonPublic|BindingFlags.Public|BindingFlags.Instance|BindingFlags.Static;
  static readonly Type Owner=typeof(FixedEffectWorker),Reader=typeof(FixedEffectWorker).GetNestedType("Reader",BindingFlags.NonPublic);
  static int count;
  static void Assert(bool value,string description) {count++;if(!value)throw new Exception(description);}
  static object Field(object target,string name) {return target.GetType().GetField(name,Hidden).GetValue(target);}
  static bool Release(bool entered,bool returned,bool created,bool exited,bool output,bool error) {
   return (bool)Owner.GetMethod("ReleaseAllowed",Hidden,null,new[]{typeof(bool),typeof(bool),typeof(bool),typeof(bool),typeof(bool),typeof(bool)},null).Invoke(null,new object[]{entered,returned,created,exited,output,error});
  }
  static object NewReader(Stream stream) {
   return Reader.GetConstructor(Hidden,null,new[]{typeof(StreamReader)},null).Invoke(new object[]{new StreamReader(stream,Encoding.UTF8,true,4096)});
  }
  static Task<string> TaskOf(object reader) {return ((TaskCompletionSource<string>)Field(reader,"Completion")).Task;}
  static void RunReader(object reader) {
   var thread=(Thread)Field(reader,"Thread");thread.Start();Assert(thread.Join(5000),"Reader did not complete bounded managed input");
  }
  sealed class ReadFailure : Stream {
   public override bool CanRead {get{return true;}} public override bool CanSeek {get{return false;}} public override bool CanWrite {get{return false;}}
   public override long Length {get{throw new NotSupportedException();}} public override long Position {get{throw new NotSupportedException();}set{throw new NotSupportedException();}}
   public override int Read(byte[] b,int o,int c) {throw new IOException("controlled read failure");}
   public override void Flush(){} public override long Seek(long a,SeekOrigin b){throw new NotSupportedException();}
   public override void SetLength(long l){throw new NotSupportedException();} public override void Write(byte[] b,int o,int c){throw new NotSupportedException();}
  }
  sealed class MeasuredMemory : MemoryStream {
   internal long Bytes;
   internal MeasuredMemory(byte[] bytes):base(bytes){}
   public override int Read(byte[] b,int o,int c){int n=base.Read(b,o,c);Bytes+=n;return n;}
  }
  sealed class GatedRead : MemoryStream {
   internal readonly ManualResetEvent Entered=new ManualResetEvent(false),Release=new ManualResetEvent(false);
   public override int Read(byte[] b,int o,int c) {Entered.Set();Release.WaitOne();return 0;}
  }
  public static int Main() {
   for(int mask=0;mask<64;mask++) {
    bool entered=(mask&1)!=0,returned=(mask&2)!=0,created=(mask&4)!=0,exited=(mask&8)!=0,output=(mask&16)!=0,error=(mask&32)!=0;
    bool expected=(!entered||returned)&&(!created||(exited&&output&&error));
    Assert(Release(entered,returned,created,exited,output,error)==expected,"Ownership gate mismatch "+mask);
   }
   Assert(!Release(true,false,false,false,true,true),"Unknown create cannot release");
   Assert(!Release(true,true,true,true,false,true),"Joined stdout without EOF cannot release");
   Assert(!Release(true,true,true,true,true,false),"Joined stderr without EOF cannot release");
   Assert(IntPtr.Size==8,"Requires x64 managed host");
   Assert(Marshal.SizeOf(Owner.GetNestedType("ExtendedStartup",BindingFlags.NonPublic))==112,"STARTUPINFOEX x64 layout");
   Assert(Marshal.SizeOf(Owner.GetNestedType("ProcessInformation",BindingFlags.NonPublic))==24,"PROCESS_INFORMATION x64 layout");
   var info=new ProcessStartInfo();info.EnvironmentVariables.Clear();info.EnvironmentVariables["WINDIR"]="C:\\Windows";info.EnvironmentVariables["TEMP"]="C:\\Тест";
   var build=Owner.GetMethod("BuildEnvironment",Hidden);string block=(string)build.Invoke(null,new object[]{info});
   Assert(block=="TEMP=C:\\Тест\0WINDIR=C:\\Windows\0\0","Sorted explicit Unicode environment");
   info.EnvironmentVariables["ALLUSERSPROFILE"]="C:\\ProgramData";
   string restoredBlock=(string)build.Invoke(null,new object[]{info});
   Assert(restoredBlock.StartsWith("ALLUSERSPROFILE=C:\\ProgramData\0",StringComparison.Ordinal),"Trusted known-folder expansion variable rejected");
   info.EnvironmentVariables.Remove("ALLUSERSPROFILE");
   info.EnvironmentVariables["DOTNET_STARTUP_HOOKS"]="untrusted";bool rejected=false;
   try{build.Invoke(null,new object[]{info});}catch(TargetInvocationException e){rejected=e.InnerException is InvalidOperationException;}
   Assert(rejected,"Unapproved environment variable accepted");
   info.EnvironmentVariables.Remove("DOTNET_STARTUP_HOOKS");rejected=false;
   try{info.EnvironmentVariables["TEMP"]="bad\0tail";build.Invoke(null,new object[]{info});}
   catch(ArgumentException){rejected=true;}catch(TargetInvocationException e){rejected=e.InnerException is InvalidOperationException;}
   Assert(rejected,"Embedded NUL accepted");
   string expectedText=new string('x',180000)+"Привет 世界\r\n";
   byte[] bytes=Encoding.UTF8.GetBytes(expectedText);var measured=new MeasuredMemory(bytes);var good=NewReader(measured);RunReader(good);
   Assert((bool)Field(good,"Eof"),"Large capture has no EOF");Assert(TaskOf(good).GetAwaiter().GetResult()==expectedText,"Capture truncation or Unicode loss");Assert(measured.Bytes==bytes.Length,"Complete capture not drained");
   var broken=NewReader(new ReadFailure());var healthy=NewReader(new MemoryStream(Encoding.UTF8.GetBytes("other channel")));
   RunReader(broken);RunReader(healthy);Assert(!(bool)Field(broken,"Eof"),"Read failure invented EOF");Assert(TaskOf(broken).IsFaulted,"Read failure lost");Assert(TaskOf(healthy).Result=="other channel","Failed reader suppressed independent stream");
   var discardStream=new MeasuredMemory(bytes);var discard=NewReader(discardStream);var injected=new IOException("controlled accumulator failure");Reader.GetField("Failure",Hidden).SetValue(discard,injected);RunReader(discard);
   Assert((bool)Field(discard,"Eof")&&discardStream.Bytes==bytes.Length,"Failed accumulator did not drain full stream");Assert(TaskOf(discard).IsFaulted,"Failed accumulator became success");Assert(Object.ReferenceEquals(TaskOf(discard).Exception.InnerException,injected),"Original capture failure replaced");
   byte[] bom=Encoding.Unicode.GetPreamble(),utf16=Encoding.Unicode.GetBytes("Русский BOM");var joined=new byte[bom.Length+utf16.Length];Buffer.BlockCopy(bom,0,joined,0,bom.Length);Buffer.BlockCopy(utf16,0,joined,bom.Length,utf16.Length);var detected=NewReader(new MemoryStream(joined));RunReader(detected);Assert(TaskOf(detected).Result=="Русский BOM","BOM compatibility lost");
   var gatedStream=new GatedRead();var gated=NewReader(gatedStream);
   var readerThread=(Thread)Field(gated,"Thread");readerThread.Start();Assert(gatedStream.Entered.WaitOne(5000),"Gated reader did not start");
   var owner=Activator.CreateInstance(Owner,true);Exception joinFailure=null;var joinDone=new ManualResetEvent(false);
   var waiter=new Thread(()=>{try{Owner.GetMethod("JoinReader",Hidden).Invoke(owner,new[]{gated,(object)true});}catch(Exception e){joinFailure=e;}finally{joinDone.Set();}});
   waiter.Start();Thread.Sleep(50);waiter.Interrupt();
   Assert(!joinDone.WaitOne(100),"Interrupted join escaped before EOF");
   gatedStream.Release.Set();Assert(waiter.Join(5000),"Interrupted join never resumed");Assert(joinFailure==null,"Interrupted join leaked exception");Assert((bool)Field(gated,"Eof"),"Interrupted join returned without EOF");
   Console.WriteLine("FIXED_EFFECT_MANAGED_PASS assertions="+count);return 0;
  }
 }
}
