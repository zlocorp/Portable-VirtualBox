// Pure behavioral model tests. Never mutate payload objects or Windows state.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using System.IO;
using System.Text;
using System.Security.Cryptography;
namespace PortableVBox {
 public static class PayloadCleanupPlanTests {
  static Type plan,entry; static int checks;
  static readonly string Hash=new string('a',64);
  static void Check(bool value,string label) {checks++;if(!value) throw new Exception("FAIL payload plan: "+label);}
  static object Invoke(Func<object> call) {try {return call();} catch(TargetInvocationException e) {throw e.InnerException;}}
  static object File(string path,long length,string hash) {return Invoke(()=>Activator.CreateInstance(entry,BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Instance,null,new object[]{path,length,hash},null));}
  static object Build(params object[] files) {Array a=Array.CreateInstance(entry,files.Length);for(int i=0;i<files.Length;i++) a.SetValue(files[i],i);return Invoke(()=>Activator.CreateInstance(plan,BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Instance,null,new object[]{a},null));}
  static object Prop(object o,string p) {return o.GetType().GetProperty(p).GetValue(o,null);}
  static void Refuses(Action call,string label) {bool failed=false;try {call();} catch(ArgumentException) {failed=true;} catch(InvalidDataException) {failed=true;} catch(InvalidOperationException) {failed=true;} Check(failed,label);}
  static void Presence(object p,PayloadJournalState s,IList<bool> exists) {Invoke(()=>{plan.GetMethod("ValidatePresence",BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Instance).Invoke(p,new object[]{s,exists});return null;});}
  public static int Main() {
   plan=typeof(PayloadCleanupPlanTests).Assembly.GetType("PortableVBox.PayloadCleanupPlan");entry=typeof(PayloadCleanupPlanTests).Assembly.GetType("PortableVBox.PayloadCleanupEntry");
   Check(plan!=null && entry!=null,"production fixed-plan implementation is missing");
   object p=Build(File("code/z",0,Hash),File("app64/sub/a",536870912,Hash));IList items=(IList)Prop(p,"Items");
   string[] expected={"app64/sub/a","code/z","app64/sub","app64","code"};
   Check(items.Count==expected.Length,"derived object count");
   for(int i=0;i<items.Count;i++) {Check((string)Prop(items[i],"Relative")==expected[i],"canonical order "+i);Check((bool)Prop(items[i],"Directory")== (i>=2),"object type "+i);}
   Check(items.IsReadOnly,"immutable plan collection");
   string canonical="F\tapp64/sub/a\t536870912\t"+Hash+"\nF\tcode/z\t0\t"+Hash+"\nD\tapp64/sub\nD\tapp64\nD\tcode\n";
   string digest;using(var h=SHA256.Create()) digest=BitConverter.ToString(h.ComputeHash(Encoding.UTF8.GetBytes(canonical))).Replace("-","").ToLowerInvariant();
   Check((string)Prop(p,"Digest")==digest,"canonical digest");
   Check((string)Prop(Build(File("app64/sub/a",536870912,Hash),File("code/z",0,Hash)),"Digest")==digest,"input-order independence");
   string[] bad={null,"","app64","other/a","/app64/a","APP64/a","app64/","app64//a","app64/./a","app64/../a","app64/a\\b","app64/a:b","app64/a\tb","app64/a\nb","app64/a\0b","app64/a*","app64/a?","app64/a<","app64/a>","app64/a|","app64/a\"","app64/a.","app64/a ","app64/CON","app64/con.txt","app64/PRN/a","app64/AUX","app64/NUL.x","app64/COM1.bin","app64/COM9","app64/LPT1","app64/LPT9.x","app64/COM\u00b9","app64/com\u00b2.bin","app64/COM\u00b3/a","app64/LPT\u00b9","app64/lpt\u00b2.bin","app64/LPT\u00b3/a","app64/"+new string('x',235),"app64/\ud800"};
   foreach(string path in bad) {string local=path;Refuses(()=>Build(File(local,0,Hash),File("code/x",0,Hash)),"reject path "+local);}
   foreach(long size in new long[]{-1,536870913,Int64.MaxValue}) {long local=size;Refuses(()=>Build(File("app64/x",local,Hash),File("code/x",0,Hash)),"invalid size");}
   foreach(string hash in new string[]{null,"",new string('A',64),new string('g',64),new string('a',63),new string('a',65)}) {string local=hash;Refuses(()=>Build(File("app64/x",0,local),File("code/x",0,Hash)),"invalid digest");}
   Refuses(()=>Build(),"empty plan");Refuses(()=>Build(File("code/x",0,Hash)),"missing app64");Refuses(()=>Build(File("app64/x",0,Hash)),"missing code");
   Refuses(()=>Build(File("app64/x",0,Hash),null,File("code/x",0,Hash)),"null entry");
   Refuses(()=>Build(File("app64/x",0,Hash),File("app64/X",0,Hash),File("code/x",0,Hash)),"case duplicate");
   Refuses(()=>Build(File("app64/A/x",0,Hash),File("app64/a/y",0,Hash),File("code/x",0,Hash)),"directory case alias");
   Refuses(()=>Build(File("app64/x",0,Hash),File("app64/X/y",0,Hash),File("code/x",0,Hash)),"file directory collision");
   var many=new List<object>();many.Add(File("code/x",0,Hash));for(int i=0;i<509;i++) many.Add(File("app64/f"+i,0,Hash));Check(((IList)Prop(Build(many.ToArray()),"Items")).Count==512,"512 accepted");many.Add(File("app64/overflow",0,Hash));Refuses(()=>Build(many.ToArray()),"513 rejected");
   int n=items.Count;
   for(int completed=0;completed<=n;completed++) for(int pending=0;pending<2;pending++) for(int complete=0;complete<2;complete++) for(int mask=0;mask<(1<<n);mask++) {
    bool valid= !(pending==1 && completed==n) && !(complete==1 && (completed!=n || pending==1));
    var present=new List<bool>();for(int i=0;i<n;i++) {bool exists=(mask&(1<<i))!=0;present.Add(exists);if(i<completed && exists) valid=false;if(i>=completed && !(pending==1 && i==completed) && !exists) valid=false;}
    var state=new PayloadJournalState(n,completed,pending==1,complete==1,Hash);
    if(valid) {Presence(p,state,present);Check(true,"valid presence permutation");} else Refuses(()=>Presence(p,state,present),"invalid presence permutation");
   }
   var all=new bool[n];for(int i=0;i<n;i++) all[i]=true;
   Refuses(()=>Presence(p,null,all),"null state");Refuses(()=>Presence(p,new PayloadJournalState(n,0,false,false,Hash),null),"null presence");
   Refuses(()=>Presence(p,new PayloadJournalState(n,0,false,false,Hash),new bool[n-1]),"presence count mismatch");
   foreach(int count in new int[]{0,n-1,n+1,513}) {int c=count;Refuses(()=>Presence(p,new PayloadJournalState(c,0,false,false,Hash),all),"state count mismatch");}
   foreach(int count in new int[]{-1,n+1}) {int c=count;Refuses(()=>Presence(p,new PayloadJournalState(n,c,false,false,Hash),all),"bad completed count");}
   foreach(string hash in new string[]{null,"",new string('A',64),new string('g',64)}) {string h=hash;Refuses(()=>Presence(p,new PayloadJournalState(n,0,false,false,h),all),"malformed state hash");}
   Console.WriteLine("PASS payload plan: "+checks+" checks");return 0;
  }
 }
}
