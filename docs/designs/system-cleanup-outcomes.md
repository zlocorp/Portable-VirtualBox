# SYSTEM cleanup outcomes: non-authorizing reference model

## Scope and approach

This is an executable **test-only specification**, not a Windows implementation.
It changes no launcher/helper/script, privilege, payload checkpoint or release gate.
The selected approach is a pure typed-record state machine and simulated writer.
A serialized resume engine is rejected because names/configuration/hashes do not
prove continuity of Windows resources. Same-live-executor progression is omitted:
there is no effect sink, resume CLI, token or native adapter to confuse with authority.
General system-cleanup retry remains a release blocker.

## Existing behavior and boundary

`scripts/privileged_session_worker.ps1:155–163` writes the partial recovery proof
before invoking cleanup and its later validation. `scripts/vbox_sup_cleanup.ps1:164–165`
creates the output directory before SDS signature/service/configuration checks at
220–236. Failure after either marker therefore cannot be classified as an attempt
that never started merely because a result file is absent. The existing
`DurableJournal` is evidence, not step authority. This model does not retrofit it.

Read-only validation can repeat without admission or effects. Admission is a
separate irreversible protocol boundary; recording ADMIT is not permission to
launch anything. The proposed immutable binding covers build mode/version, helper
and frontend hashes, portable root, protected session, SID, original controller
generation, initiating cleanup-controller generation, receipt digests and fixed
plan digest. The test fixture represents these as ten opaque bounded strings;
real verification of the claims is deliberately not implemented.

## Candidate protocol

The fixed steps are SDS unregister, driver stop, exact package removal, conditional
residual-service deletion, terminal verification. Residual deletion must remain
conditional on exact ownership and a fresh observation; absence means a verified
no-op, never a wildcard/delete fallback. The model conservatively requires the
same exited-child and postcondition evidence for every SUCCESS, even a no-op or
terminal verification. A future implementation must define its trusted executor
contract separately instead of inventing a child exit.

Events are ADMIT; alternating BEGIN(step), SUCCESS(step); then COMPLETE. SUCCESS
requires an exited zero-status child and an explicitly verified postcondition.
NO_EFFECTS is an optional terminal alternative only after ADMIT and before any
BEGIN. Its claim requires a trusted executor proving no launch, plus complete
attempt lineage, before fresh validation can even be considered. These premises
are abstract test inputs, not authenticated facts or permissions. Logs alone
cannot establish them. Missing history is never no-attempt evidence.

Every simulated append passes write, flush and readback before the acknowledged
prefix advances. Any uncertainty poisons that writer permanently. Its acknowledged
prefix may differ from whatever storage really retained, so inspection through a
poisoned writer returns UNKNOWN. There is no filesystem writer/parser, byte-level
encoding, durability promise, authentication, or power-loss guarantee here.
Typed records have bounded count and fields; order, duplicates, foreign bindings,
malformed values and late NO_EFFECTS are rejected without repair/truncation.
Hashes and JSON are not authentication. Valid-prefix rollback cannot be detected
without separately anchored complete attempt lineage.

## Decisions

- Restart with ADMIT and no terminal outcome requires inspection.
- Outstanding BEGIN is UNKNOWN regardless of apparent absence.
- Nonzero exit, timeout, launch exception or unverified postcondition is UNKNOWN.
- A SUCCESS plus a fresh matching postcondition is observationally completed.
  It grants no authority over a next same-name/config/hash resource, including a
  replacement after a completed predecessor.
- PRESENT, ABSENT and UNKNOWN are distinct. Error and delete-pending are not
  absence. Presence/absence alone does not prove a stopped-driver postcondition:
  the model uses MATCH only for an explicit step-specific verified postcondition.
- All cross-process post-admission mutations are refused. COMPLETE and current
  matching observations produce DIAGNOSTIC_COMPLETE only. Old JSON never creates
  the payload checkpoint described in `owner-bound-cleanup-resume.md`.
- Every public decision result explicitly contains `mutation_authorized=false`.
  VALIDATION_ELIGIBLE is an observational predicate only, not admission authority.

SCM handles cannot be serialized as durable native capabilities. VBoxSDS.exe,
sc.exe and pnputil resolve resources by name again, so even a retained SCM handle
would not automatically establish continuity of their targets. An opaque test
token could only model a proposed invariant, never prove real Windows API
continuity. No such token or effect adapter is included in this increment.

The MATCH fixture is an abstract supplied postcondition, not a Windows classifier.
A later successful package removal can subsume an earlier stopped-driver condition;
a future adapter must define that relation explicitly. Five MATCH values do not
constitute a demonstrated native terminal check. Malformed observation vectors (wrong container, count, non-exact-string values,
empty strings or values longer than 512 characters) cannot satisfy preflight or
fresh-postcondition predicates. They yield no observationally completed steps;
a complete history then remains INSPECTION_REQUIRED. An outstanding BEGIN still
has the stronger UNKNOWN classification. PRESENT in the validation fixture
likewise stands for supplied acceptable preflight observations, not full validation.

The trusted-no-launch and complete-lineage premises are independently supplied by
tests. This model does not discover omitted attempts, authenticate lineage or
detect contradictory external history. Supplying a false premise cannot be made
safe by hashing records. The replacement-next-resource case deliberately remains
INSPECTION_REQUIRED even when the predecessor is observationally completed.

Microsoft documents that an [OpenServiceW handle](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-openservicew)
is valid only in its calling process; the service is selected by name. A JSON
snapshot cannot transfer that handle. [DeleteService](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-deleteservice)
marks a service for deletion; removal requires all handles closed and the service
not running. Even hypothetical held-handle deletion therefore needs close plus
verified absence, without adopting a subsequently recreated same-name service.
These are sourced constraints, not an implemented continuity adapter.

## Evidence and limitations

Tests cover malformed field types/lengths and binding changes, all valid history prefixes, 781 bounded sequences over five event
symbols, 36 write/flush/readback fault boundaries, terminal/no-effects lineage,
invalid/duplicate/foreign/oversized records, unknown outcomes and non-authority.
They enumerate typed prefixes, not byte truncations, JSON encodings or hash chains.
They do not test Windows, actual process continuity, durable storage or native
service/package ownership. Further independent protocol review and disposable
Windows evidence are necessary before any production change. Existing interactive
UAC and isolated Windows 10/11 acceptance requirements remain unchanged.
