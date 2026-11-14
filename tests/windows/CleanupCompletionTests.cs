// Executes the real private sequencing method. No helper Main or native effects.
using System;
using System.Collections.Generic;
using System.Reflection;
using System.Threading.Tasks;
namespace PortableVBox {
 public static class CleanupCompletionTests {
  static int checks;
  static void Check(bool value,string reason) {++checks;if(!value) throw new Exception(reason);}
  static Task<string> Capture(string text,bool fail) {
   var task=new TaskCompletionSource<string>();
   if(fail) task.SetException(new InvalidOperationException(text));else task.SetResult(text);
   return task.Task;
  }
  static void Case(string fault,bool timely,int exit,string secondary="") {
   var events=new List<string>();bool checkpoint=false,deleted=false;Exception caught=null;
   Action<string> step=name=>{events.Add(name);if(fault==name || secondary==name) throw new InvalidOperationException(name);};
   var method=typeof(SessionHelper).GetMethod("CompleteCleanupWorker",BindingFlags.Static|BindingFlags.NonPublic);
   Check(method!=null,"Missing actual private cleanup sequencing");
   try {
    method.Invoke(null,new object[]{timely,exit,(Action)(()=>step("persist")),
     Capture("stdout",fault=="capture-out" || secondary=="capture-out"),Capture("stderr",fault=="capture-err" || secondary=="capture-err"),
     (Action)(()=>step("controller")),(Action)(()=>{step("checkpoint");checkpoint=true;}),
     (Action<string>)(text=>{Check(text=="stdout","stdout capture changed");step("write-out");}),
     (Action<string>)(text=>{Check(text=="stderr","stderr capture changed");step("write-err");}),
     (Action)(()=>step("write-facts"))});
    deleted=true; // Main can enter Continue only on normal return.
   } catch(TargetInvocationException error) {caught=error.InnerException;}
   bool eligible=timely && exit==0 && fault!="persist" && fault!="capture-out" && fault!="capture-err" && fault!="controller" && fault!="checkpoint";
   Check(checkpoint==eligible,"Checkpoint eligibility: "+fault);
   Check(deleted==(fault=="" && timely && exit==0),"Continue eligibility: "+fault);
   Check(events.Contains("write-out")== (fault!="capture-out" && secondary!="capture-out"),"Available stdout diagnostics lost: "+fault);
   Check(events.Contains("write-err")== (fault!="capture-err" && secondary!="capture-err"),"Available stderr diagnostics lost: "+fault);
   Check(events.Contains("write-facts"),"Available facts diagnostics lost: "+fault);
   if(checkpoint) {
    Check(events.IndexOf("checkpoint")<events.IndexOf("write-out"),"Checkpoint must precede stdout");
    Check(events.IndexOf("checkpoint")<events.IndexOf("write-err"),"Checkpoint must precede stderr");
    Check(events.IndexOf("checkpoint")<events.IndexOf("write-facts"),"Checkpoint must precede facts");
   }
   if(!timely) Check(caught!=null && caught.Message.Contains("deadline"),"Diagnostic fault masked deadline");
   else if(exit!=0) Check(caught!=null && caught.Message.Contains("worker rejected"),"Diagnostic fault masked worker rejection");
   else if(fault!="") Check(caught!=null && caught.Message==(fault=="capture-out"?"stdout":fault=="capture-err"?"stderr":fault),"Primary failure changed: "+fault);
   else Check(caught==null,"Unexpected successful-path refusal");
  }
  public static int Main() {
   foreach(string fault in new[]{"","persist","capture-out","capture-err","controller","checkpoint","write-out","write-err","write-facts"}) {
    Case(fault,true,0);Case(fault,true,70);Case(fault,false,0);Case(fault,false,70);
   }
   foreach(string primary in new[]{"persist","capture-out","capture-err","controller","checkpoint"})
    foreach(string diagnostic in new[]{"write-out","write-err","write-facts"}) Case(primary,true,0,diagnostic);
   Case("capture-out",true,0,"capture-err");
   Console.WriteLine("CLEANUP_COMPLETION_PASS checks="+checks);return 0;
  }
 }
}
