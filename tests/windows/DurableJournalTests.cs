// Filesystem-only regression: compiles the real implementation, never the helper entrypoint.
using System;
using System.IO;
using System.Diagnostics;
using System.Threading;
using System.Reflection;
using System.Text;
using System.Security.Cryptography;
namespace PortableVBox {
    public static class DurableJournalTests {
        static int checks;
        static Type journal;
        static string directory;
        static readonly string binding="{\"pid\":42,\"created\":\"133000001\",\"root\":\"C:\\\\Переносной\",\"cycle\":1}";
        static void Check(bool ok,string label) { ++checks;if(!ok) throw new Exception("FAIL durable journal: "+label); }
        static object Call(object receiver,string name,params object[] args) {
            var method=journal.GetMethod(name,BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Static|BindingFlags.Instance);
            try { return method.Invoke(receiver,args); }
            catch(TargetInvocationException e) { throw e.InnerException; }
        }
        static object Get(object value,string name) {return value.GetType().GetProperty(name).GetValue(value,null);}
        static void Refuses(Action action,string label) {
            bool refused=false;
            try {action();} catch(InvalidDataException) {refused=true;} catch(InvalidOperationException) {refused=true;} catch(IOException) {refused=true;} catch(ArgumentException) {refused=true;}
            Check(refused,label);
        }
        static string PathFor(string name) {return Path.Combine(directory,name+".journal");}
        static string Digest(byte[] bytes) {using(var h=SHA256.Create()) return BitConverter.ToString(h.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();}
        static object Read(string path,string expected) {return Call(null,"Inspect",path,expected);}
        static object Create(string path,string expected,string intent) {return Call(null,"CreateNew",path,expected,intent);}
        static void Dispose(object value) {((IDisposable)value).Dispose();}
        static byte[] Bytes(string value) {return new UTF8Encoding(false,true).GetBytes(value);}
        static byte[] ReadBytes(string path) {
            using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite))
            using(var m=new MemoryStream()) {f.CopyTo(m);return m.ToArray();}
        }
        static void Same(byte[] before,string path,string label) {Check(Digest(before)==Digest(ReadBytes(path)),label);}
        static string Rehash(string line) {var fields=line.Split('\t');string prefix=String.Join("\t",fields,0,4);return prefix+"\t"+Digest(Bytes(prefix))+"\n";}
        // Fail only at the actual disk boundary, retaining all other real
        // FileStream effects. No test hooks or alternate writer in production.
        sealed class BrokenFile : FileStream {
            internal string Failure="";
            internal BrokenFile(string path) : base(path,FileMode.CreateNew,FileAccess.Write,FileShare.Read) {}
            public override void Write(byte[] bytes,int offset,int count) {
                if(Failure=="write") {base.Write(bytes,offset,Math.Max(1,count/2));base.Flush(true);throw new IOException("injected partial write");}
                base.Write(bytes,offset,count);
            }
            public override void Flush(bool durable) {base.Flush(durable);if(Failure=="flush") throw new IOException("injected uncertain flush");}
            protected override void Dispose(bool disposing) {base.Dispose(disposing);if(Failure=="close") throw new IOException("injected close failure");}
        }
        static void StorageFailure(string kind) {
            string path=PathFor("failure-"+kind),header="PVBJ1\t"+Convert.ToBase64String(Bytes(binding))+"\n";
            var file=new BrokenFile(path);byte[] headerBytes=Bytes(header);file.Write(headerBytes,0,headerBytes.Length);file.Flush(true);
            object writer=Activator.CreateInstance(journal,BindingFlags.Instance|BindingFlags.NonPublic,null,new object[]{file,Digest(headerBytes)},null);
            try {
                if(kind=="close") {
                    Call(writer,"Append",0,"Prepare");file.Failure=kind;
                    Refuses(()=>Dispose(writer),"close error is propagated");
                } else {
                    file.Failure=kind;Refuses(()=>Call(writer,"Append",0,"Prepare"),kind+" failure is propagated");
                }
                file.Failure="";byte[] before=ReadBytes(path);
                Refuses(()=>Call(writer,"Append",0,"Prepare"),"uncertain/disposed writer cannot retry after "+kind);
                Same(before,path,"failed writer preserves evidence for "+kind);
                if(kind=="write") Refuses(()=>Read(path,binding),"partial write is never complete evidence");
                else Check(!(bool)Get(Read(path,binding),"Complete"),"uncertain "+kind+" cannot imply completion");
            } finally {file.Failure="";Dispose(writer);}
        }
        static void KilledWriter(int phase) {
            string path=PathFor("killed-"+phase);
            var info=new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName,"--child \""+path+"\" "+phase);
            info.UseShellExecute=false;info.RedirectStandardOutput=true;info.CreateNoWindow=true;
            using(var child=Process.Start(info)) {
                try {
                    var signal=child.StandardOutput.ReadLineAsync();
                    Check(signal.Wait(10000) && signal.Result=="DURABLE","owned child reached durable boundary");
                    // Terminate only the exact fixture child that we created.
                    child.Kill();Check(child.WaitForExit(10000),"owned child termination observed");
                    object inspection=Read(path,binding);
                    Check((int)Get(inspection,"Count")==phase+1 && !(bool)Get(inspection,"Complete"),"abrupt process exit remains pending at phase "+phase);
                } finally {if(!child.HasExited) {child.Kill();child.WaitForExit();}}
            }
        }
        public static int Main(string[] args) {
            journal=typeof(DurableJournalTests).Assembly.GetType("PortableVBox.DurableJournal");
            if(args.Length==3 && args[0]=="--child") {
                object childWriter=Create(args[1],binding,"Prepare");
                if(args[2]=="1") Call(childWriter,"WorkerExited","exit=0;deadline=True");
                Console.WriteLine("DURABLE");Console.Out.Flush();Thread.Sleep(Timeout.Infinite);return 1;
            }
            directory=Path.Combine(Path.GetTempPath(),"pvbox-journal-"+Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            try {
                journal=typeof(DurableJournalTests).Assembly.GetType("PortableVBox.DurableJournal");
                Check(journal!=null,"production durable journal is missing");
                string path=PathFor("roundtrip");
                object writer=Create(path,binding,"Prepare");
                try {
                    object first=Read(path,binding);
                    Check((int)Get(first,"Count")==1 && !(bool)Get(first,"Complete"),"flushed intent is pending and readable while writer held");
                    Check((string)Get(first,"Intent")=="Prepare","intent survives restart inspection");
                    Refuses(()=>Create(path,binding,"Prepare"),"create-new never overwrites existing evidence");
                    Refuses(()=>{using(var concurrent=new FileStream(path,FileMode.Open,FileAccess.Write,FileShare.ReadWrite)) {}},"retained writer denies competing write");
                    Refuses(()=>File.Delete(path),"retained writer denies deletion");
                    Refuses(()=>Read(path,binding+" "),"changed owner binding refuses");
                    Refuses(()=>Call(writer,"Complete","done"),"completion cannot skip worker result");
                    Call(writer,"WorkerExited","exit=0;deadline=True");
                    object exited=Read(path,binding);
                    Check((int)Get(exited,"Count")==2 && !(bool)Get(exited,"Complete"),"worker exit alone never completes operation");
                    Refuses(()=>Call(writer,"WorkerExited","exit=0"),"duplicate worker result refuses");
                    Call(writer,"Complete","controller-alive;helper-checks-complete");
                    Refuses(()=>Call(writer,"Complete","replay"),"terminal journal refuses replay");
                } finally {Dispose(writer);}
                object result=Read(path,binding);
                Check((int)Get(result,"Count")==3 && (bool)Get(result,"Complete"),"complete flushed sequence roundtrip");
                Check((string)Get(result,"LastPayload")=="controller-alive;helper-checks-complete","final evidence roundtrip");
                byte[] original=File.ReadAllBytes(path);
                Refuses(()=>Create(path,binding,"Finish"),"closed journal cannot be recreated");
                Same(original,path,"duplicate creation preserves all bytes");
                string partial=PathFor("pending");writer=Create(partial,binding,"Recover");Dispose(writer);
                Check(!(bool)Get(Read(partial,binding),"Complete"),"interrupted attempt remains unresolved after close");
                Refuses(()=>Call(writer,"WorkerExited","exit=0"),"disposed writer cannot continue");

                // Literal frame mutations are re-hashed independently, so these
                // assertions exercise semantics as well as checksum validation.
                string text=Encoding.UTF8.GetString(original);string[] lines=text.Split('\n');
                string corrupt=PathFor("corrupt");
                for(int length=0;length<original.Length;length++) {
                    // Prefixes ending at a complete record are valid but pending.
                    if(length>0 && original[length-1]==10) {
                        File.WriteAllBytes(corrupt,new ArraySegment<byte>(original,0,length).ToArray());
                        if(length==Bytes(lines[0]+"\n").Length) Refuses(()=>Read(corrupt,binding),"header-only prefix refuses");
                        else Check(!(bool)Get(Read(corrupt,binding),"Complete"),"complete record prefix remains pending");
                        continue;
                    }
                    File.WriteAllBytes(corrupt,new ArraySegment<byte>(original,0,length).ToArray());
                    Refuses(()=>Read(corrupt,binding),"truncation at byte "+length);
                }
                string[] malformed={
                    lines[0]+"\n",text+"\n",text+"unexpected",text.Replace("PVBJ1","PVBJ2"),
                    text.Replace("WORKER_EXIT","WORKER_ExIT"),text.Replace("INTENT","COMPLETE"),
                    text.Replace("\n","\r\n"),text.Substring(0,text.Length-1),
                    lines[0]+"\n"+lines[2]+"\n"+lines[1]+"\n"+lines[3]+"\n",
                    lines[0]+"\n"+lines[1]+"\n"+lines[1]+"\n",
                    lines[0]+"\n"+Rehash(lines[1].Replace("0\tINTENT", "7\tINTENT")),
                    lines[0]+"\n"+Rehash(lines[1].Replace("INTENT", "UNKNOWN")),
                    lines[0]+"\n"+Rehash(lines[1].Replace("UHJlcGFyZQ==", "!invalid!"))
                };
                foreach(string bad in malformed) {File.WriteAllBytes(corrupt,Bytes(bad));Refuses(()=>Read(corrupt,binding),"malformed journal refuses");}
                foreach(string payload in new[]{"", "UHJlcGFyZQ== ", "/w==", Convert.ToBase64String(Bytes("Unknown")), Convert.ToBase64String(Bytes(new string('x',8193)))}) {
                    string[] fields=lines[1].Split('\t');fields[2]=payload;
                    File.WriteAllBytes(corrupt,Bytes(lines[0]+"\n"+Rehash(String.Join("\t",fields))));
                    Refuses(()=>Read(corrupt,binding),"independently rehashed invalid payload refuses");
                }
                string[] wrongChain=lines[2].Split('\t');wrongChain[3]=new string('0',64);
                File.WriteAllBytes(corrupt,Bytes(lines[0]+"\n"+lines[1]+"\n"+Rehash(String.Join("\t",wrongChain))));
                Refuses(()=>Read(corrupt,binding),"rehashed wrong previous digest refuses");
                var bitflip=(byte[])original.Clone();bitflip[bitflip.Length-5]^=1;File.WriteAllBytes(corrupt,bitflip);
                Refuses(()=>Read(corrupt,binding),"checksum mismatch refuses");
                File.WriteAllBytes(corrupt,new byte[65537]);Refuses(()=>Read(corrupt,binding),"oversized file refuses before parsing");
                Refuses(()=>Create(PathFor("empty-binding"),"","Prepare"),"empty binding refuses");
                Refuses(()=>Create(PathFor("large-binding"),new string('x',4097),"Prepare"),"large binding refuses");
                Refuses(()=>Create(PathFor("bad-kind"),binding,"Unregister"),"new privileged action not accepted as intent");
                Refuses(()=>Create(PathFor("invalid-utf8"),binding+"\ud800","Prepare"),"invalid UTF-16 cannot enter UTF-8 journal");
                Refuses(()=>Create(PathFor("multibyte-binding"),new string('я',2049),"Prepare"),"binding byte limit cannot be bypassed with Unicode");
                writer=Create(PathFor("exact-limits"),new string('я',2048),"Prepare");
                try {
                    Call(writer,"WorkerExited",new string('я',4096));
                    Check((int)Get(Read(PathFor("exact-limits"),new string('я',2048)),"Count")==2,"exact UTF-8 byte bounds roundtrip");
                } finally {Dispose(writer);}
                writer=Create(PathFor("limits"),binding,"Finish");
                try {
                    Refuses(()=>Call(writer,"WorkerExited",new string('x',8193)),"oversized event refuses");
                    Refuses(()=>Call(writer,"WorkerExited",new string('я',4097)),"event byte bound cannot be bypassed with Unicode");
                    Call(writer,"WorkerExited","exit=70;ошибка");
                    Check(!(bool)Get(Read(PathFor("limits"),binding),"Complete"),"failed worker evidence remains pending");
                } finally {Dispose(writer);}
                foreach(string name in new[]{"empty-binding","large-binding","bad-kind","invalid-utf8"}) Check(!File.Exists(PathFor(name)),"invalid create leaves no evidence path: "+name);
                foreach(string failure in new[]{"write","flush","close"}) StorageFailure(failure);
                KilledWriter(0);KilledWriter(1);
                Console.WriteLine("PASS durable journal: "+checks+" real storage/framing/interruption assertions");return 0;
            } catch(Exception e) {Console.Error.WriteLine(e);return 1;}
            finally {Directory.Delete(directory,true);}
        }
        // Framework 4.x has no ArraySegment.ToArray without Linq.
        static byte[] ToArray(this ArraySegment<byte> value) {byte[] bytes=new byte[value.Count];Array.Copy(value.Array,value.Offset,bytes,0,value.Count);return bytes;}
    }
}
