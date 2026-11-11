// TEST ONLY. Managed behavioral contracts, no native calls.
using System;
namespace PortableVBox {
 public static class NativeChildCaptureTests {
  static void Check(bool value,string message) { if(!value) throw new Exception(message); }
  static void Refuses(Action action) { bool refused=false; try { action(); } catch(InvalidOperationException) { refused=true; } Check(refused,"one-shot refusal"); }
  public static int RunManaged() {
   var proof=new ChildCaptureProof();
   proof.UseOnce(); Refuses(proof.UseOnce);
   proof.BeforeCreate(); Refuses(proof.BeforeCreate);
   Check(!proof.CanRelease,"Unknown create return must retain owner");
   proof.CreateReturned(true); Refuses(()=>proof.CreateReturned(false));
   Check(!proof.Complete,"Creation is not exit or EOF");
   proof.ExitObserved=true;
   Check(!proof.Complete,"Child exit without EOF is incomplete");
   proof.StdoutEof=true; Check(!proof.Complete,"One stream EOF is not both streams EOF"); proof.StderrEof=true;
   Check(!proof.Complete,"EOF does not settle pending I/O");
   proof.IoTerminal=true;
   Check(proof.CanRelease && !proof.Complete,"Terminal operations allow close, not complete");
   proof.HandlesClosed=true;
   Check(proof.Complete,"All actual independent facts complete");
   proof.Fault(); Check(proof.Unknown && proof.Complete,"Fault remains unknown after safe release");
   var missing=new ChildCaptureProof(); missing.UseOnce(); missing.BeforeCreate(); missing.Fault();
   missing.ExitObserved=true;missing.IoTerminal=true;missing.HandlesClosed=true;missing.StdoutEof=true;missing.StderrEof=true;
   Check(!missing.CanRelease && !missing.Complete,"Synthetic completion cannot cure missing create return");
   var premature=new ChildCaptureProof(); Refuses(()=>premature.CreateReturned(true)); Refuses(premature.BeforeCreate);
   var rejected=new ChildCaptureProof(); rejected.UseOnce(); rejected.BeforeCreate(); rejected.CreateReturned(false); rejected.IoTerminal=true;
   Check(rejected.CanRelease && !rejected.Complete,"Rejected create can clean but never complete capture");
   var output=new PipeCapture();var bytes=new byte[4096]; bytes[0]=255;
   output.Receive(bytes,4096); output.Fault(1);
   for(int i=0;i<40;i++) output.Receive(bytes,4096);
   Check(output.Unknown && output.Total==167936 && output.RetainedCount==4096 && output.Discarded==163840,"Fault must continue bounded discard");
   var operation=new PipeOperationProof(); operation.BeforeIssue(); operation.CancelReturned(0);
   Check(!operation.SafeToRelease,"Cancellation is not terminal"); operation.ExactTerminal();
   Check(operation.SafeToRelease,"Exact I/O terminal permits storage release");
   var close=new PipeCloseProof(); close.BeforeClose(); close.Returned(false);
   Check(close.Unresolved && !close.Confirmed,"Known failed close is unresolved"); Refuses(close.BeforeClose);
   var lostClose=new PipeCloseProof(); lostClose.BeforeClose();
   Check(lostClose.Unresolved,"Lost close return remains unresolved"); Refuses(lostClose.BeforeClose);
   Console.WriteLine("managed fixed-child contracts PASS");return 0;
  }
 }
}
