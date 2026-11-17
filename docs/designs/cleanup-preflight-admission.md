# Cleanup preflight before irreversible admission

## Goal and choice

Allow a fresh explicit Finish/Recover after a read-only full-cleanup preflight
failure, without deleting evidence or replaying any system effect. The user has
delegated autonomous continuation; this is an implementation choice, not a new
claim of approval of a specific protocol.

Resetting attempt ledgers is rejected: retained child/image handles do not bind
SCM/PnP object generations. A durable NO_LAUNCH recovery protocol is deferred.
Instead, perform all existing full-cleanup read-only preflight before committing
its one-shot proof and output directory. Partial-preparation recovery is unchanged.

## Boundary

The fixed worker supplies the prospective proof in memory to the already embedded
full-cleanup script. That script validates the same owner/session proof, driver
receipts, package identity, publisher signatures, service configuration and idle
state. Before its first system operation it writes the proof with CreateNew and
Flush(true), creates the output directory and retains existing one-shot semantics.
File-based legacy callers keep their existing proof validation. Read-only SDS
preflight errors now occur before cleanup output/report creation for those callers
as well; command errors still propagate, but no finalization report is promised
for a failure before admission. Existing worker journals retain the attempt error.

Prospective proof is accepted only in the protected PrivilegedSession and
RecoverySession paths, at the exact expected session-local proof path. Existing
proofs/cleanup state always refuse; no deletion, overwrite or reconstruction is
permitted. A crash or write failure after admission stays blocked. New calls
repeat validation from scratch; they never reuse a successful preflight as authority.

This reduces pre-effect stuck sessions. It is not system-effect retry, arbitrary
power-loss recovery, a durable resource capability or Windows workstation approval.

## Verification

Execute actual script logic with controlled observers and effect tripwires: each
preflight failure must leave no proof/output and perform no effects; a corrected
retry must reach admission; after any admission failure a later attempt must
refuse. Cover changed owner/resources, partial results, missing/foreign receipts,
proof path mismatches, existing markers, write/flush failures and legacy callers.
Run existing source suite, actual Windows PowerShell 5.1 fixture and affected
disposable-host workflows. Independently review before publication.
