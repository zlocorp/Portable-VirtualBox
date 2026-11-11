# Owner-bound cleanup continuation

## Intent

Finish safe work after an operational cleanup failure without treating a missing
file, a same-name Windows service, or an old JSON claim as ownership. This extends
the one-VM boundary only. It does not add automatic cleanup, a general OS rescue
command, updater behavior, or permission to run on a primary workstation.

## Approaches

- Removing replay markers and running the old worker again is rejected: it loses
  the distinction between effects not started, committed effects and uncertainty.
- A single universal replay engine is rejected: Windows service/package names
  do not provide a durable object generation. Recreated resources cannot simply
  inherit the old session's authority.
- Selected incremental approach: first continue only private payload removal
  after a new durable, owner-bound system-teardown checkpoint. Then separately
  evaluate forward-only continuation after committed system-effect outcomes.
  An uncommitted native effect is never automatically retried.

## First increment: payload only

The helper writes a new checkpoint only after the fixed worker has exited
successfully, its exact cleanup receipt is verified and fresh system observations
confirm no VBox processes, services, driver or exact published INF remains.
Original acquisition and owner receipts are preserved. The checkpoint binds:

- Same compiled helper hash, frontend hash, build mode and protocol version.
- Protected session path, portable root, SID, original PID/generation and cycle.
- The initiating cleanup controller generation.
- Original pinned manifest bytes, the resulting fixed file/directory plan hash,
  exact published INF name and digests of acquisition/cleanup evidence.
- Original volume identity, 128-bit file ID, creation time and type for every file
  and directory. Matching bytes or ACL alone cannot adopt a replacement object.

A crash after worker success but before the new durable checkpoint remains
unsupported: cleanup JSON alone cannot reconstruct this authority. A preparation
created by an older helper is not adopted. A missing or malformed
checkpoint does not authorize new cleanup. The checkpoint itself never authorizes
any service, driver or package command.

The existing Finish/Recover verbs recognize the new payload branch before full
payload staging. They still independently authenticate the live medium controller,
root/build/SID and protected ACLs. Recover requires the original PID to be absent;
a recycled or unreadable PID fails closed. A different initiating cleanup
controller must also be absent. The privileged mutex remains mandatory, and an
abandoned mutex still refuses continuation.

This branch does not execute PowerShell, restage app64/code, rerun system teardown,
delete receipts, or recursively remove the session. It deletes only a fixed plan
of the original 185 pinned files, their exact protected manifest, the six embedded
scripts, and their expected empty directories. It preserves all audit evidence.

A separate bounded append-only journal binds the owner/checkpoint and plan. Events
are exactly BEGIN(i), DONE(i), advancing from index zero, then COMPLETE. Each
record is flushed and reread before it authorizes progress. A failed write/flush
makes that writer unusable. Torn, malformed, reordered, foreign or oversized
journals are rejected without rewriting or truncating them.

Before continuation, all remaining paths are checked against the fixed plan:
completed objects must be absent; only the pending BEGIN object may be either
exactly present (same original volume/file ID/creation time/type, verified through
one retained handle) or absent; future objects must still be exactly present. Changed,
extra, linked, reparse, multiply linked, wrong-owner or unsafe-ACL objects block
before deletion. A file deletion after BEGIN but before DONE can therefore be
finished by confirming absence, without acquiring authority over a new object.
Deletion is requested through that verified handle, the handle is closed, and
explicit native NOT_FOUND must be observed before DONE. Access denied, sharing
violations or delete-pending are unknown, not absence. Expected empty-directory
deletion follows the same rule. Only the target lease is released; session/store/
root ancestry remains locked continuously. Current system quiescence
and controller liveness are checked again during progress and at completion.

A new journal may be created from an intact authenticated checkpoint only while
all planned objects are still present and exact. This covers a failure before
journal creation, not missing history after partial removal. The final existing
payload-removed marker is written only after journal COMPLETE and verified absence;
its boolean content alone is not authority. Fully completed attempts remain
non-replayable. Arbitrary power-loss recovery is not promised.

## Subsequent system-effect increment

Keep current one-shot system cleanup until a separately reviewed protocol exists.
The candidate order is SDS unregister, driver stop, exact package removal,
conditional exact residual-service deletion, then teardown verification. Durable
success permits skipping only an effect whose current postcondition still matches.
A durable intent without a committed outcome is unknown, even when current names
or hashes look unchanged. No force, wildcard deletion, direct driver-file deletion,
registry deletion fallback, or ownership reconstruction is permitted.

## Evidence gates

1. Executable journal tests at every committed boundary and every byte truncation;
   corrupt/foreign/order/size/concurrency/uncertain-writer negative cases.
2. Native file-only plan/ownership tests, including missing pending versus future
   files, recreated completed entries, extra content, reparse/hardlinks, wrong
   bindings, locked files, and original receipt/VM-data preservation.
3. Disposable Windows helper tests after selected payload deletion boundaries,
   same-controller Finish and absent-original-controller Recover, without rerunning
   service effects. Preserve before/after evidence and failed runs.
4. Independent review of the mutation boundary before publishing implementation.
5. Full source/Python/native checks and affected exact-commit CI. Interactive UAC
   and isolated Windows 10/11 acceptance remain separate release requirements.
