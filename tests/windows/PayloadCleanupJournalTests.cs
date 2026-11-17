// Real temporary-file tests only. No helper entrypoint or Windows mutation.
using System;
using System.IO;
using System.Reflection;
using System.Text;
using System.Security.Cryptography;
namespace PortableVBox {
 public static class PayloadCleanupJournalTests {
  static Type journal; static string root; static int checks;
  const string Binding="private-payload:Переносной:fixed-plan";
  static readonly UTF8Encoding Utf8=new UTF8Encoding(false,true);
  static void Check(bool ok,string label) {++checks;if(!ok) throw new Exception("FAIL payload journal: "+label);}
  static object Call(object receiver,string name,params object[] args) {
   try {return journal.GetMethod(name,BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Static|BindingFlags.Instance).Invoke(receiver,args);}
   catch(TargetInvocationException e) {throw e.InnerException;}
  }
  static object Prop(object value,string name) {return value.GetType().GetProperty(name).GetValue(value,null);}
  static void Refuses(Action action,string label) {bool no=false;try {action();} catch(ArgumentException) {no=true;} catch(InvalidDataException) {no=true;} catch(IOException) {no=true;} catch(InvalidOperationException) {no=true;} Check(no,label);}
  static string PathFor(string name) {return Path.Combine(root,name);}
  static string Hash(byte[] bytes) {using(var h=SHA256.Create()) return BitConverter.ToString(h.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();}
  static byte[] Read(string path) {using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite)) using(var m=new MemoryStream()) {f.CopyTo(m);return m.ToArray();}}
  static object Inspect(string path) {return Call(null,"Inspect",path,Binding,3);}
  static void State(object state,int completed,bool pending,bool complete,string label) {
   Check((int)Prop(state,"StepCount")==3 && (int)Prop(state,"Completed")==completed && (bool)Prop(state,"Pending")==pending && (bool)Prop(state,"Complete")==complete,label);
   Check(((string)Prop(state,"LastHash")).Length==64,label+" hash");
  }
  static void RejectBytes(string name,byte[] bytes) {
   string p=PathFor("reject");File.WriteAllBytes(p,bytes);
   Refuses(()=>Inspect(p),name+" inspect");Refuses(()=>Call(null,"OpenResume",p,Binding,3),name+" resume");
   Check(Hash(bytes)==Hash(Read(p)),name+" preserves rejected bytes");
  }
  static string Event(int sequence,string kind,int index,string previous) {
   string prefix=sequence+"\t"+kind+"\t"+index+"\t"+previous;
   return prefix+"\t"+Hash(Utf8.GetBytes(prefix))+"\n";
  }
  // Fault injection lives only in tests. Production keeps its private FileStream
  // constructor and offers no replacement writer or public injection seam.
  sealed class BrokenFile : FileStream {
   string failure=""; bool flushed;
   internal string Failure {get {return failure;} set {failure=value;flushed=false;}}
   internal BrokenFile(string path) : base(path,FileMode.Open,FileAccess.ReadWrite,FileShare.Read) {}
   public override void Write(byte[] bytes,int offset,int count) {
    if(Failure=="write") {base.Write(bytes,offset,Math.Max(1,count/2));base.Flush(true);throw new IOException("partial write");}
    if(Failure=="lost-write") return;
    base.Write(bytes,offset,count);
   }
   public override void Flush(bool durable) {base.Flush(durable);flushed=true;if(Failure=="flush") throw new IOException("uncertain flush");}
   public override int Read(byte[] bytes,int offset,int count) {
    if(Failure=="read" || (Failure=="verify" && flushed)) throw new IOException("read failure");
    return base.Read(bytes,offset,count);
   }
   protected override void Dispose(bool disposing) {base.Dispose(disposing);if(Failure=="close") throw new IOException("close failure");}
  }
  static void StorageFailure(string failure) {
   string path=PathFor("failure-"+failure);
   using(var created=(IDisposable)Call(null,"CreateNew",path,Binding,3)) {}
   var file=new BrokenFile(path);
   object writer=Activator.CreateInstance(journal,BindingFlags.NonPublic|BindingFlags.Instance,null,new object[]{file,Utf8.GetString(Read(path)),3},null);
   try {
    object before=Prop(writer,"State");file.Failure=failure;
    if(failure=="close") Refuses(()=>((IDisposable)writer).Dispose(),"close failure propagated");
    else Refuses(()=>Call(writer,"Begin",0),failure+" propagated");
    Check(Object.ReferenceEquals(before,Prop(writer,"State")),failure+" cannot publish in-memory authority");
    file.Failure="";byte[] bytes=Read(path);
    Refuses(()=>Call(writer,"Begin",0),failure+" permanently disables retry");
    Check(Hash(bytes)==Hash(Read(path)),failure+" retry preserves evidence");
    if(failure=="write") Refuses(()=>Inspect(path),"partial write fails closed");
   } finally {file.Failure="";((IDisposable)writer).Dispose();}
  }
  static void ResumeBarrierFailure(string failure) {
   string path=PathFor("resume-barrier-"+failure);
   using(var created=(IDisposable)Call(null,"CreateNew",path,Binding,3)) {Call(created,"Begin",0);}
   byte[] bytes=Read(path);
   string header=Utf8.GetString(bytes).Split('\n')[0]+"\n";
   var file=new BrokenFile(path);file.Failure=failure;
   object writer=null;bool refused=false;
   try {
    try {writer=Activator.CreateInstance(journal,BindingFlags.NonPublic|BindingFlags.Instance,null,new object[]{file,header,3},null);}
    catch(TargetInvocationException e) {if(e.InnerException is IOException || e.InnerException is InvalidDataException) refused=true;else throw;}
    Check(refused && writer==null,"resume durable barrier rejects "+failure+" before publishing writer");
   } finally {
    file.Failure="";if(writer!=null) ((IDisposable)writer).Dispose();else file.Dispose();
   }
   Check(Hash(bytes)==Hash(Read(path)),"failed resume barrier preserves bytes for "+failure);
   State(Inspect(path),0,true,false,"failed resume barrier leaves pending evidence");
  }
  public static int Main() {
   root=Path.Combine(Path.GetTempPath(),"pvbox-payload-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
   try {
    journal=typeof(PayloadCleanupJournalTests).Assembly.GetType("PortableVBox.PayloadCleanupJournal");
    Check(journal!=null,"production payload journal is missing");
    string path=PathFor("roundtrip");object writer=Call(null,"CreateNew",path,Binding,3);
    State(Prop(writer,"State"),0,false,false,"header-only is valid");
    Refuses(()=>Call(null,"CreateNew",path,Binding,3),"create never overwrites");
    if(Environment.OSVersion.Platform==PlatformID.Win32NT) {
     Refuses(()=>Call(null,"OpenResume",path,Binding,3),"concurrent resume denied");
     Refuses(()=>{using(var f=new FileStream(path,FileMode.Open,FileAccess.ReadWrite,FileShare.ReadWrite)) {}},"competing writer denied");
    } else Console.WriteLine("SKIP Windows FileShare writer-denial checks: this runtime is not Windows");
    ((IDisposable)writer).Dispose();
    for(int i=0;i<3;i++) {
     writer=Call(null,"OpenResume",path,Binding,3);
     State(Prop(writer,"State"),i,false,false,"resume before begin");
     byte[] before=Read(path);
     Refuses(()=>Call(writer,"Done",i),"done without begin");Refuses(()=>Call(writer,"Begin",i+1),"skip begin");Refuses(()=>Call(writer,"Begin",-1),"negative index");Refuses(()=>Call(writer,"Complete"),"early complete");
     Check(Hash(before)==Hash(Read(path)),"invalid transitions preserve bytes");
     Call(writer,"Begin",i);State(Inspect(path),i,true,false,"begin durable");
     Refuses(()=>Call(writer,"Begin",i),"duplicate begin");Refuses(()=>Call(writer,"Done",i+1),"wrong done");
     ((IDisposable)writer).Dispose();writer=Call(null,"OpenResume",path,Binding,3);
     State(Prop(writer,"State"),i,true,false,"pending begin resumes only this step");
     Call(writer,"Done",i);State(Inspect(path),i+1,false,false,"done durable");
     Refuses(()=>Call(writer,"Done",i),"duplicate done");((IDisposable)writer).Dispose();
    }
    writer=Call(null,"OpenResume",path,Binding,3);Call(writer,"Complete");State(Inspect(path),3,false,true,"completion durable");
    Refuses(()=>Call(writer,"Complete"),"duplicate completion");Refuses(()=>Call(writer,"Begin",3),"post-complete begin");
    ((IDisposable)writer).Dispose();Refuses(()=>Call(writer,"Begin",0),"disposed writer");
    writer=Call(null,"OpenResume",path,Binding,3);State(Prop(writer,"State"),3,false,true,"completed resume cannot append");Refuses(()=>Call(writer,"Complete"),"resumed complete sealed");((IDisposable)writer).Dispose();
    byte[] original=Read(path);string text=Utf8.GetString(original);string[] lines=text.Split('\n');
    for(int n=0;n<=original.Length;n++) {
     byte[] prefix=new byte[n];Array.Copy(original,prefix,n);
     if(n>0 && prefix[n-1]==10) {
      string p=PathFor("prefix");File.WriteAllBytes(p,prefix);object s=Inspect(p);
      int events=Utf8.GetString(prefix).Split('\n').Length-2;
      State(s,Math.Min(events/2,3),events<6 && events%2==1,events==7,"valid committed prefix "+n);
      using(var resume=(IDisposable)Call(null,"OpenResume",p,Binding,3)) {}
     } else RejectBytes("truncation "+n,prefix);
    }
    Refuses(()=>Call(null,"Inspect",path,Binding+" ",3),"binding mismatch");Refuses(()=>Call(null,"OpenResume",path,Binding,2),"count mismatch");
    foreach(string bad in new[]{text.Replace("PVBC1","PVBC2"),text+"\n",text+lines[1]+"\n",text.Replace("\n","\r\n"),"\ufeff"+text,text.Replace("\t3\t","\t03\t"),text.Replace(Convert.ToBase64String(Utf8.GetBytes(Binding)),Convert.ToBase64String(Utf8.GetBytes(Binding))+" ")}) RejectBytes("malformed canonical framing",Utf8.GetBytes(bad));
    string header=lines[0]+"\n",previous=Hash(Utf8.GetBytes(header));
    foreach(string bad in new[]{Event(0,"DONE",0,previous),Event(0,"BEGIN",1,previous),Event(1,"BEGIN",0,previous),Event(0,"COMPLETE",3,previous),Event(0,"BEGIN",0,new string('0',64)),Event(0,"BEGIN",0,previous)+Event(1,"BEGIN",0,lines[1].Split('\t')[4])}) RejectBytes("rehashed semantic violation",Utf8.GetBytes(header+bad));
    byte[] flip=(byte[])original.Clone();flip[flip.Length-4]^=1;RejectBytes("digest corruption",flip);
    byte[] invalid=(byte[])original.Clone();invalid[0]=255;RejectBytes("invalid UTF8",invalid);
    RejectBytes("size bound",new byte[262145]);
    foreach(int count in new[]{0,-1,513,Int32.MaxValue}) Refuses(()=>Call(null,"CreateNew",PathFor("badcount"),Binding,count),"step bound");
    foreach(string b in new[]{new string('x',4097),new string('я',2049),"\ud800"}) Refuses(()=>Call(null,"CreateNew",PathFor("badbinding"),b,1),"UTF8 binding bound");
    Check(!File.Exists(PathFor("badcount")) && !File.Exists(PathFor("badbinding")),"invalid inputs leave no files");
    string limit=PathFor("limit");writer=Call(null,"CreateNew",limit,new string('я',2048),512);
    for(int i=0;i<512;i++) {Call(writer,"Begin",i);Call(writer,"Done",i);}Call(writer,"Complete");((IDisposable)writer).Dispose();
    Check((bool)Prop(Call(null,"Inspect",limit,new string('я',2048),512),"Complete"),"maximum legal journal roundtrip");
    foreach(string failure in new[]{"write","flush","read","verify","lost-write","close"}) StorageFailure(failure);
    ResumeBarrierFailure("verify");ResumeBarrierFailure("flush");
    Refuses(()=>Call(null,"CreateNew",PathFor("empty-binding"),"",1),"empty binding rejected");
    Check(!File.Exists(PathFor("empty-binding")),"empty binding leaves no file");
    Console.WriteLine("PASS payload cleanup journal: "+checks+" filesystem assertions");return 0;
   } catch(Exception e) {Console.Error.WriteLine(e);return 1;}
   finally {Directory.Delete(root,true);}
  }
 }
}
