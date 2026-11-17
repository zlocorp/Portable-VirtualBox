// TEST ONLY. Managed decision tests are not native Windows evidence.
using System;

namespace PortableVBox {
 public static class NativePipeTransportTests {
  static int checks;
  internal static void Check(bool condition,string name) {
   ++checks;
   if(!condition) throw new InvalidOperationException(name);
  }
  static void Refuses(Action action,string name) {
   bool rejected=false;
   try { action(); } catch(InvalidOperationException) { rejected=true; }
   Check(rejected,name);
  }
  internal static byte Pattern(int offset,int seed) { return (byte)((offset*37+seed)%256); }
  internal static ulong PatternHash(int length,int seed) {
   ulong hash=14695981039346656037UL;
   for(int i=0;i<length;i++) hash=unchecked((hash^Pattern(i,seed))*1099511628211UL);
   return hash;
  }
  public static int RunManaged() {
   checks=0;
   try {
    var preparation=new PipePreparationProof();
    preparation.BeforePrepare();
    bool publishedSetupComplete=false,publishedConsumed=false;
    Check(preparation.Attempted && !publishedSetupComplete && !publishedConsumed,
     "Setup attempt must be recorded before allocation even when setup never completed");
    Refuses(()=>preparation.BeforePrepare(),"Failed partial setup cannot be retried and overwrite owned slots");
    var operation=new PipeOperationProof();
    Check(operation.SafeToRelease,"Never-issued storage is releasable");
    operation.BeforeIssue();
    Check(!operation.SafeToRelease,"Issuing must root storage BEFORE the call returns");
    operation.Pending();
    Refuses(()=>operation.BeforeIssue(),"One outstanding operation per slot");
    operation.SignalOnly();
    Check(!operation.SafeToRelease,"Signaled event is not terminal I/O proof");
    operation.CancelReturned(0);
    Check(!operation.SafeToRelease,"CancelIoEx success is only a request");
    operation.CancelReturned(1168);
    Check(!operation.SafeToRelease,"ERROR_NOT_FOUND is not completion");
    operation.WaitFailed();
    Check(!operation.SafeToRelease && operation.Unknown,"WAIT_FAILED retains storage");
    operation.ExactTerminal();
    Check(operation.SafeToRelease && operation.Unknown,"Actual completion permits release, UNKNOWN stays sticky");
    Check(operation.Issued==1 && operation.Terminal==1,"Exact operation proof has balanced issue/completion");
    Refuses(()=>operation.ExactTerminal(),"Duplicate completion is rejected");
    operation.BeforeIssue();
    operation.Unavailable();
    int publishedHandles=0,uninitializedStatus=0;
    Check(publishedHandles==0 && uninitializedStatus==0 && !operation.SafeToRelease,
     "Empty published state cannot certify unknown submission");
    operation.CancelReturned(1168);
    Check(!operation.SafeToRelease,"False not-found counterexample retains unknown submission");
    Refuses(()=>operation.ExactTerminal(),"Unavailable submission cannot be cured by a possibly stale query");
    Check(!operation.SafeToRelease && operation.Unknown,"Unavailable submission is irreversibly retained");

    var reused=new PipeOperationProof();
    reused.BeforeIssue(); reused.Pending(); reused.ExactTerminal(1);
    reused.BeforeIssue(); reused.Pending(); reused.SignalOnly();
    Refuses(()=>reused.ExactTerminal(1),"Previous generation completion cannot retire current operation");
    Check(!reused.SafeToRelease,"Stale event/completion keeps current storage live");
    reused.ExactTerminal(2);
    Check(reused.SafeToRelease,"Only current generation terminal fact permits release");

    foreach(bool returnKnown in new[]{false,true}) {
     var closing=new PipeCloseProof();
     closing.BeforeClose();
     if(returnKnown) closing.Returned(false);
     int publishedHandle=0;
     Check(publishedHandle==0 && closing.Unresolved,"Unobserved/failed close cannot be cured by zero published handle");
     Refuses(()=>closing.BeforeClose(),"Uncertain numeric handle cannot be closed again");
     if(returnKnown) {
      Refuses(()=>closing.Returned(true),"Known failed close cannot be overwritten by a later unrelated success");
      Check(closing.Unresolved,"Rejected replacement close evidence must retain owner");
     }
    }
    var closed=new PipeCloseProof();
    closed.BeforeClose(); closed.Returned(true);
    Check(!closed.Unresolved && closed.Confirmed,"Actual successful close permits fixture release");
    Refuses(()=>closed.BeforeClose(),"Even a confirmed stale handle cannot be closed again");

    var noData=new PipeCapture();
    noData.ObserveTerminalError(232);
    Check(noData.Unknown && !noData.Eof,"ERROR_NO_DATA is failed transport, not clean EOF");
    var expired=new PipeCapture();
    expired.ExpireEofBudget();
    Check(expired.Unknown && !expired.Eof,"EOF timeout retains UNKNOWN without inventing EOF");
    expired.ObserveTerminalError(109);
    Check(expired.Unknown && expired.Eof,"Actual later EOF does not clear timeout UNKNOWN");

    foreach(int size in new[]{0,1,17,4096,65536,196731}) {
     var capture=new PipeCapture();
     byte[] chunk=new byte[4096];
     for(int position=0;position<size;) {
      int count=Math.Min(chunk.Length,size-position);
      for(int i=0;i<count;i++) chunk[i]=Pattern(position+i,0);
      capture.Receive(chunk,count);
      position+=count;
     }
     Check(capture.Total==size,"All raw bytes must be counted");
     Check(capture.RetainedCount==Math.Min(size,65536),"Retained output must stop at 64 KiB");
     Check(capture.Discarded==Math.Max(0,size-65536),"Exact discarded count");
     Check(capture.Hash==PatternHash(size,0),"NUL and non-UTF bytes must survive streaming hash");
     Check(!capture.Eof,"Empty/data reads never invent EOF");
     for(int i=0;i<capture.RetainedCount;i++)
      if(capture.Retained[i]!=Pattern(i,0)) throw new InvalidOperationException("Retained prefix mismatch");
     Check(!capture.Unknown,"Healthy capture is known");
     capture.ObserveEof();
     Check(capture.Eof,"EOF is a separate observation");
    }
    foreach(int site in new[]{1,2}) {
     var capture=new PipeCapture();
     byte[] chunk=new byte[4096];
     for(int i=0;i<chunk.Length;i++) chunk[i]=Pattern(i,71);
     capture.Receive(chunk,chunk.Length);
     capture.Fault(site);
     for(int i=0;i<40;i++) capture.Receive(chunk,chunk.Length);
     Check(capture.FaultSite==site,"Actual controlled fault site is retained");
     Check(capture.Unknown && capture.Total==41L*4096,"Fault must not stop counting/draining");
     Check(capture.RetainedCount==4096,"Fault switches to discard without growing storage");
     Check(capture.Discarded==40L*4096,"Fault discard count is exact");
     Check(capture.Hash==PatternHash(41*4096,71),"Fault preserves raw byte hash");
     capture.ObserveEof();
     Check(capture.Unknown && capture.Eof,"EOF never clears UNKNOWN");
    }
    var bad=new PipeCapture();
    bool bounds=false;
    try { bad.Receive(new byte[1],2); } catch(ArgumentOutOfRangeException) { bounds=true; }
    Check(bounds && bad.Total==0,"Invalid byte counts fail before copying");
    Console.WriteLine("{\"kind\":\"managed_pipe_contracts\",\"status\":\"PASS\",\"checks\":"+checks+",\"native_calls\":0,\"mutation_authorized\":false}");
    return 0;
   } catch(Exception error) {
    Console.WriteLine("{\"kind\":\"managed_pipe_contracts\",\"status\":\"FAIL\",\"checks\":"+checks+",\"native_calls\":0,\"mutation_authorized\":false}");
    Console.Error.WriteLine(error.Message);
    return 1;
   }
  }
 }
}
