// TEST-ONLY protocol tests. No SCM/Windows API behavior is established here.
using System;
using System.Threading;
namespace PortableVBox.ServiceIdentityModel {
 public static class ServiceIdentityObservationTests {
  static int checks;
  static void Check(bool value,string name){checks++;if(!value)throw new Exception(name);}
  sealed class Service : IObservedService {
   internal string State="Running";internal int Queries,Closes;internal bool FailQuery,FailClose;
   internal ManualResetEvent Entered,Release;
   public string Query(){Interlocked.Increment(ref Queries);if(Entered!=null){Entered.Set();if(!Release.WaitOne(3000))throw new Exception("test query timeout");}if(FailQuery)throw new InvalidOperationException("observation unavailable");return State;}
   public void Close(){Interlocked.Increment(ref Closes);if(FailClose)throw new InvalidOperationException("close unavailable");}
  }
  static void Refused(Action call,string name){bool refused=false;try{call();}catch(InvalidOperationException){refused=true;}Check(refused,name);}
  public static int Main(){
   var a=new Service();var context=new ObservationContext(StopOutcome.Nonzero);var lease=context.Capture(a);
   Check(context.Query(lease)=="Running","live exact handle observed");
   // Identical name/config are deliberately not protocol inputs. Replacement object
   // has a different state; no method can look it up from a durable selector.
   var replacement=new Service {State="Stopped"};
   Check(context.Query(lease)=="Running"&&replacement.Queries==0,"old capability cannot adopt replacement");
   Refused(()=>context.Query(new ObservationContext.Lease(context,replacement)),"forged same-owner token refused");
   var other=new ObservationContext(StopOutcome.Success);var otherLease=other.Capture(replacement);
   Refused(()=>other.Query(lease),"cross-context query refused");
   Refused(()=>context.Close(otherLease),"cross-context close refused");
   Refused(()=>context.Capture(replacement),"context cannot reopen or recapture");
   a.FailQuery=true;Check(context.Query(lease)=="UNKNOWN","query exception unknown");
   a.FailQuery=false;a.State="Stopped";Check(context.Query(lease)=="Stopped","observation retry allowed");
   Check(context.OriginalStop==StopOutcome.Nonzero&&!context.MutationAuthorized,"observation does not repair original failure");
   context.Close(lease);int queries=a.Queries;
   Check(context.Query(lease)=="UNKNOWN"&&a.Queries==queries,"closed token never queries backend");
   context.Close(lease);Check(a.Closes==1,"close is terminal and not repeated");
   Refused(()=>context.Capture(replacement),"closed context cannot adopt identical replacement");
   foreach(StopOutcome outcome in Enum.GetValues(typeof(StopOutcome))){
    var c=new ObservationContext(outcome);var s=new Service{State="Stopped"};var t=c.Capture(s);
    for(int i=0;i<3;i++)Check(c.Query(t)=="Stopped","repeat reads observed");
    Check(c.OriginalStop==outcome&&!c.MutationAuthorized,"all stop outcomes preserve zero authority");
    c.Lose(t);Check(c.Query(t)=="UNKNOWN"&&s.Queries==3,"lost capability terminal");
    Refused(()=>c.Capture(new Service()),"loss never reopens");
   }
   var badClose=new Service{FailClose=true};var failed=new ObservationContext(StopOutcome.Unknown);var ft=failed.Capture(badClose);
   failed.Close(ft);failed.Close(ft);Check(badClose.Closes==1&&failed.Query(ft)=="UNKNOWN","failed close never revives capability");
   var malformed=new Service{State=null};var mc=new ObservationContext(StopOutcome.Success);var mt=mc.Capture(malformed);
   Check(mc.Query(mt)=="UNKNOWN","null observation unknown");malformed.State="invented";Check(mc.Query(mt)=="UNKNOWN","unrecognized observation unknown");
   Refused(()=>mc.Query(null),"null capability refused");
   // Real threads exercise model serialization, not a mock claim of serialization.
   using(var entered=new ManualResetEvent(false))using(var release=new ManualResetEvent(false))using(var closeStarted=new ManualResetEvent(false))using(var closeDone=new ManualResetEvent(false)){
    var s=new Service{Entered=entered,Release=release};var c=new ObservationContext(StopOutcome.Late);var t=c.Capture(s);
    Exception queryError=null,closeError=null;string result=null;
    var reader=new Thread(()=>{try{result=c.Query(t);}catch(Exception e){queryError=e;}});
    var closer=new Thread(()=>{closeStarted.Set();try{c.Close(t);}catch(Exception e){closeError=e;}finally{closeDone.Set();}});
    reader.Start();Check(entered.WaitOne(2000),"query entered");closer.Start();Check(closeStarted.WaitOne(2000),"close invoked");
    bool closedEarly=closeDone.WaitOne(100);release.Set();Check(reader.Join(3000)&&closer.Join(3000),"threads complete");
    Check(!closedEarly&&queryError==null&&closeError==null&&result=="Running"&&s.Closes==1,"close waits for exact in-flight query");
    Check(c.Query(t)=="UNKNOWN"&&s.Queries==1,"no query after serialized close");
   }
   Console.WriteLine("SERVICE_IDENTITY_MODEL_PASS checks="+checks+" native_calls=0 mutation_authorized=false");return 0;
  }
 }
}
