// TEST ONLY. No production transport or mutation authority.
using System;

namespace PortableVBox {
 internal sealed class PipePreparationProof {
  internal bool Attempted { get; private set; }
  internal void BeforePrepare() {
   if(Attempted) throw new InvalidOperationException("Preparation already attempted");
   Attempted=true;
  }
 }
 internal sealed class PipeCloseProof {
  internal bool Attempted,Confirmed;
  bool returnObserved;
  internal bool Unresolved { get { return Attempted && !Confirmed; } }
  internal void BeforeClose() {
   if(Attempted) throw new InvalidOperationException("Handle close already attempted");
   Attempted=true;
  }
  internal void Returned(bool success) {
   if(!Attempted || returnObserved) throw new InvalidOperationException("No new close result");
   returnObserved=true;
   Confirmed=success;
  }
 }
 internal sealed class PipeOperationProof {
  internal bool MayBeReferenced;
  internal bool Unknown;
  internal bool SubmissionUnavailable;
  internal int Issued;
  internal int Terminal;
  internal bool SafeToRelease { get { return !MayBeReferenced; } }
  internal void BeforeIssue() {
   if(MayBeReferenced) throw new InvalidOperationException("Operation already outstanding");
   MayBeReferenced=true;
   ++Issued;
  }
  internal void Pending() {
   if(!MayBeReferenced) throw new InvalidOperationException("No issued operation");
  }
  internal void SignalOnly() { }
  internal void CancelReturned(int error) { }
  internal void Unavailable() { Unknown=true; SubmissionUnavailable=true; }
  internal void WaitFailed() { Unknown=true; }
  internal void ExactTerminal() {
   if(!MayBeReferenced || SubmissionUnavailable) throw new InvalidOperationException("No trustworthy operation to complete");
   ++Terminal;
   MayBeReferenced=false;
  }
  internal void ExactTerminal(int generation) {
   if(generation!=Issued) throw new InvalidOperationException("Stale operation generation");
   ExactTerminal();
  }
 }
 internal sealed class PipeCapture {
  internal const int Capacity=65536;
  internal readonly byte[] Retained=new byte[Capacity];
  internal int RetainedCount;
  internal long Total;
  internal ulong Hash=14695981039346656037UL;
  internal bool Unknown;
  internal bool Eof;
  internal int FaultSite;
  internal long Discarded { get { return Total-RetainedCount; } }
  internal void Receive(byte[] bytes,int count) {
   if(bytes==null || count<0 || count>bytes.Length || count>4096)
    throw new ArgumentOutOfRangeException("count");
   if(Eof) throw new InvalidOperationException("Data after EOF");
   for(int i=0;i<count;i++) Hash=unchecked((Hash^bytes[i])*1099511628211UL);
   Total+=count;
   if(!Unknown) {
    int keep=Math.Min(count,Capacity-RetainedCount);
    if(keep!=0) Buffer.BlockCopy(bytes,0,Retained,RetainedCount,keep);
    RetainedCount+=keep;
   }
  }
  internal void Fault(int site) { Unknown=true; FaultSite=site; }
  internal void ObserveEof() { Eof=true; }
  internal void ObserveTerminalError(int error) {
   if(error==109) ObserveEof(); else Fault(3);
  }
  internal void ExpireEofBudget() { Fault(4); }
 }
}
