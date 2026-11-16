// TEST-ONLY candidate protocol; not wired to production or any native API.
// The supplied object represents admission observation, NOT creation provenance.
using System;
namespace PortableVBox.ServiceIdentityModel {
 internal enum StopOutcome { Success, Nonzero, Late, Unknown }
 internal interface IObservedService { string Query(); void Close(); }
 internal sealed class ObservationContext {
  internal sealed class Lease {
   internal readonly ObservationContext Owner;
   internal readonly IObservedService Service;
   internal bool Terminal;
   internal Lease(ObservationContext owner,IObservedService service){Owner=owner;Service=service;}
  }
  readonly object sync=new object();Lease exact;bool captured;
  internal readonly StopOutcome OriginalStop;
  internal bool MutationAuthorized {get{return false;}}
  internal ObservationContext(StopOutcome outcome){OriginalStop=outcome;}
  internal Lease Capture(IObservedService service){lock(sync){
   if(captured||service==null)throw new InvalidOperationException("No recapture/adoption");
   captured=true;exact=new Lease(this,service);return exact;
  }}
  void Require(Lease lease){if(lease==null||!Object.ReferenceEquals(lease,exact)||!Object.ReferenceEquals(lease.Owner,this))throw new InvalidOperationException("Foreign capability");}
  internal string Query(Lease lease){lock(sync){
   Require(lease);if(lease.Terminal)return "UNKNOWN";
   try{string state=lease.Service.Query();return state=="Stopped"||state=="Running"||state=="StopPending"?state:"UNKNOWN";}
   catch{return "UNKNOWN";}
  }}
  internal void Close(Lease lease){lock(sync){
   Require(lease);if(lease.Terminal)return;lease.Terminal=true;
   try{lease.Service.Close();}catch{/* Close uncertainty is terminal, never reopen. */}
  }}
  internal void Lose(Lease lease){lock(sync){Require(lease);lease.Terminal=true;}}
 }
}
