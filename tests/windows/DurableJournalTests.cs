// Filesystem-only regression: compiles the real implementation, never the helper entrypoint.
using System;
using System.IO;
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
        static void Same(byte[] before,string path,string label) {Check(Digest(before)==Digest(File.ReadAllBytes(path)),label);}
        static string Rehash(string line) {var fields=line.Split('\t');string prefix=String.Join("\t",fields,0,4);return prefix+"\t"+Digest(Bytes(prefix))+"\n";}
        public static int Main() {
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
                    if(length>0 && original[length-1]==10) continue;
                    File.WriteAllBytes(corrupt,new ArraySegment<byte>(original,0,length).ToArray());
                    Refuses(()=>Read(corrupt,binding),"truncation at byte "+length);
                }
                string[] malformed={
                    text+"\n",text+"unexpected",text.Replace("PVBJ1","PVBJ2"),
                    text.Replace("WORKER_EXIT","WORKER_ExIT"),text.Replace("INTENT","COMPLETE"),
                    text.Replace("\n","\r\n"),text.Substring(0,text.Length-1),
                    lines[0]+"\n"+lines[2]+"\n"+lines[1]+"\n"+lines[3]+"\n",
                    lines[0]+"\n"+lines[1]+"\n"+lines[1]+"\n",
                    lines[0]+"\n"+Rehash(lines[1].Replace("0\tINTENT", "7\tINTENT")),
                    lines[0]+"\n"+Rehash(lines[1].Replace("INTENT", "UNKNOWN")),
                    lines[0]+"\n"+Rehash(lines[1].Replace("UHJlcGFyZQ==", "!invalid!"))
                };
                foreach(string bad in malformed) {File.WriteAllBytes(corrupt,Bytes(bad));Refuses(()=>Read(corrupt,binding),"malformed journal refuses");}
                var bitflip=(byte[])original.Clone();bitflip[bitflip.Length-5]^=1;File.WriteAllBytes(corrupt,bitflip);
                Refuses(()=>Read(corrupt,binding),"checksum mismatch refuses");
                File.WriteAllBytes(corrupt,new byte[65537]);Refuses(()=>Read(corrupt,binding),"oversized file refuses before parsing");
                Refuses(()=>Create(PathFor("empty-binding"),"","Prepare"),"empty binding refuses");
                Refuses(()=>Create(PathFor("large-binding"),new string('x',4097),"Prepare"),"large binding refuses");
                Refuses(()=>Create(PathFor("bad-kind"),binding,"Unregister"),"new privileged action not accepted as intent");
                Refuses(()=>Create(PathFor("invalid-utf8"),binding+"\ud800","Prepare"),"invalid UTF-16 cannot enter UTF-8 journal");
                writer=Create(PathFor("limits"),binding,"Finish");
                try {
                    Refuses(()=>Call(writer,"WorkerExited",new string('x',8193)),"oversized event refuses");
                    Call(writer,"WorkerExited","exit=70;ошибка");
                    Check(!(bool)Get(Read(PathFor("limits"),binding),"Complete"),"failed worker evidence remains pending");
                } finally {Dispose(writer);}
                foreach(string name in new[]{"empty-binding","large-binding","bad-kind","invalid-utf8"}) Check(!File.Exists(PathFor(name)),"invalid create leaves no evidence path: "+name);
                Console.WriteLine("PASS durable journal: "+checks+" real storage/framing/interruption assertions");return 0;
            } catch(Exception e) {Console.Error.WriteLine(e);return 1;}
            finally {Directory.Delete(directory,true);}
        }
        // Framework 4.x has no ArraySegment.ToArray without Linq.
        static byte[] ToArray(this ArraySegment<byte> value) {byte[] bytes=new byte[value.Count];Array.Copy(value.Array,value.Offset,bytes,0,value.Count);return bytes;}
    }
}
