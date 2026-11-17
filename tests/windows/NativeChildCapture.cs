// TEST ONLY. Independent facts; no serialized authority.
using System;
namespace PortableVBox {
 internal sealed class ChildCaptureProof {
  bool used,entered,returned,created;
  internal bool ExitObserved,StdoutEof,StderrEof,IoTerminal,HandlesClosed,Unknown;
  internal void UseOnce() { if(used) throw new InvalidOperationException(); used=true; }
  internal void BeforeCreate() { if(!used || entered) throw new InvalidOperationException("Create entry is one-shot"); entered=true; }
  internal void CreateReturned(bool success) { if(!entered || returned) throw new InvalidOperationException("No new create return"); returned=true;created=success; }
  internal void Fault() { Unknown=true; }
  internal bool CanRelease { get { return (!entered || returned) && IoTerminal && (!created || ExitObserved); } }
  internal bool Complete { get { return created && entered && returned && ExitObserved && StdoutEof && StderrEof && IoTerminal && HandlesClosed; } }
 }
}
