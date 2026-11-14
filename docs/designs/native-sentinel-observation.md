# Test-only exact sentinel observation

Status: preflight, pure Task 1, native-composition and final integration reviews
are complete. Published source `519056432b4d9bd045140d2ba2bbe924e5c135e9` passed
both natural Windows native runs and all 11 triggered workflows on attempt 1.
Independent artifact review accepted nine capture, three environment and four
file-only image cases per native run. See the [execution record](../EXECUTION-2026-11-11-native-sentinel-observation.md)
for exact checkouts, same-tree PR evidence, artifact digests and inference limits.
The [implementation plan](../plans/2026-11-11-native-sentinel-observation.md)
preserves the staged contract and verification sequence. This is test-only
acceptance; fixed-image process composition and production lifetime repair remain
outside this increment.

## Motivation and scope

At source `b2229c53213470ec030dd5944416e9b25ccfe414`, native PR run
[43090294982](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090294982)
failed the existing sentinel assertion in `CaptureFault` and `EvidenceFault`.
Both cases observed exit 0, both EOFs, complete fixed-body counts and confirmed
parent-owner release. The actual parent sentinel remained unsignaled. The recorded
stdout hash reconstructs exactly from the unchanged body and the old preamble
reporting successful `SetEvent` on the numeric candidate. The artifact does not
identify that child-local object. These observations support the already documented
conservative numeric-reuse failure; they are not proof of inherited sentinel
identity, stream corruption or a lifetime defect.

The same-source push run
[43090280267](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090280267)
passed nine capture, three environment and four file-only image cases. That does
not turn the PR failure into a pass. Preserve both checkpoints and their artifacts;
do not rerun the failed source merely to obtain green.

Replace only this test fixture's numeric `SetEvent` probe. Keep the nine capture
cases, three environment cases, current JSONL schemas, finite streams, original
process/thread ownership, exact I/O terminal results, independent EOF/exit/close
facts, sticky UNKNOWN and one-shot behavior. No production code, arbitrary child,
user Windows host, VirtualBox operation, driver, service, elevation, network,
descendant control, merge or release is added. All diagnostics remain
`mutation_authorized=false` and never authorize cleanup.

## Approaches considered

1. **Duplicate the numeric candidate before opening a reference.** Rejected.
   The candidate can be an arbitrary runtime handle. Microsoft discourages
   `DuplicateHandle` for completion ports and sockets, and warns that duplicating
   sockets interferes with internal reference counting. It is not a harmless
   general snapshot operation for this input. See [DuplicateHandle](https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-duplicatehandle).
2. **Check only handle validity or the parent event's unsignaled state.** Rejected.
   Validity cannot distinguish another object; an inherited but untouched sentinel
   can remain unsignaled. Waiting on an arbitrary candidate is also unsuitable:
   waits can affect other synchronization object types.
3. **Open an owned reference and query identity without modifying the candidate.**
   Selected proposal. It preserves the three inherited standard handles and treats
   reference allocation at the candidate number explicitly. No handle enumeration,
   undocumented object-name query or extra inherited reference is required.

## Parent-created reference provenance

Each `ChildCaptureOwner` generates one token with `Guid.NewGuid().ToString("N")`.
The accepted token grammar is exactly 32 lowercase ASCII hexadecimal characters.
The only event name is `Local\pvbox-fixed-sentinel-` followed by that token. The
token is an identifier, not a credential or a malicious-peer authentication claim.

Create a manual-reset, initially nonsignaled event using the existing private DACL
descriptor, with inheritance initially disabled. Clear last error immediately
before creation and capture it immediately afterward. A NULL result is failure.
A non-NULL result with `ERROR_ALREADY_EXISTS` (183) is also refusal: do not change
that existing object's state or inheritance flags. Close only the newly returned
owned reference through the existing exact close proof. Guard acquisition with
the owner's native-return-unknown state. See [CreateEventW](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-createeventw).

Only after fresh creation is established, use the existing `SetInherit` operation
on this owned parent handle. Continue excluding it from the exact three-entry
stdin/stdout/stderr allowlist. Retain the original sentinel handle until the child
has exited, capture is settled and existing release rules permit closing it. The
child receives exactly the fixed case, positive decimal handle and token; it
reconstructs the name rather than accepting an arbitrary name or namespace.

Holding the original event keeps the named object alive, so the child does not
need to create a replacement. An object-name collision is refused, not retried
with another name during the same case. Same-user interference remains outside
this trusted, finite fixture's claims. See [OpenEventW](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-openeventw).

## One shared argument parser

`NativeSentinelObservation.cs` supplies the actual pure parser used by the child:
`SentinelArguments.TryParse(string[] args, out SentinelArguments parsed,
out int rejectionExit)`. Its immutable result exposes `CaseName`, `Candidate`
(Int64) and `Token`; only a successful parse may construct it. It does not reference
the parent's `CaptureCase` enum or require parent/native source files.

Require exactly three non-null arguments. The ordinal, case-sensitive case
allowlist is Empty, Binary, Large, Nonzero, Exit259, PostCreateFault, CaptureFault,
EvidenceFault, WithheldEof and EnvironmentObservation. The handle is canonical
positive ASCII decimal: first character 1..9, remaining characters 0..9, length
1..19 and checked value no greater than Int64.MaxValue (9223372036854775807).
Reject signs, leading zeroes, whitespace, non-ASCII digits, zero and overflow.
Validate the token with the exact lowercase hexadecimal grammar above.

Wrong array shape or null element returns false/exit 90; an unsupported case
returns false/91; invalid handle or token returns false/92. On failure `parsed`
is null. On success return true/0. Parsing performs no native operations. Child
`Main` must call this exact parser and consume its immutable result; do not add a
separate unused parser for tests or retain duplicate parsing logic in `Main`.
The observer accepts the parsed result, not another raw command or case selector.

## Query sequence, errors and ownership

The numeric candidate is borrowed. Never close, duplicate, signal, reset, wait on
or change flags on it. The only new child-owned handle is the named reference.
Construct and root its one-shot observation owner before native acquisition.
The child stores that observer in a static `observerRoot` before `ObserveOnce`.
Keep it rooted through Empty's early return, normal output and all exception
returns; an outer `finally` may call `GC.KeepAlive(observerRoot)` but must not close
or retry it. Never clear the root while ownership is unresolved. A cleanup attempt
belongs only to the observer's one-shot close path, not another `finally`,
`Dispose`, finalizer or exit branch.

1. Validate the case, token and positive x64 handle before native calls. Preserve
   the existing closed case allowlist and reject additional arguments.
2. Open the reconstructed name with `OpenEventW(SYNCHRONIZE, FALSE, name)`.
   `SYNCHRONIZE` is `0x00100000`; it does not include `EVENT_MODIFY_STATE`.
   Actual candidate operations are query-only, and the child performs no wait.
   A failed or unavailable open yields UNKNOWN. See [synchronization access rights](https://learn.microsoft.com/en-us/windows/win32/sync/synchronization-object-security-and-access-rights).
3. Require `CompareObjectHandles(reference, reference)` to return TRUE. Missing
   API, exception, unavailable return or unsuccessful self-comparison is UNKNOWN.
4. If the returned reference number equals the candidate, classify
   `ReferenceAllocatedAtCandidate`. Do not interpret self-comparison as inheritance.
5. Otherwise call `GetHandleInformation(candidate)`. Known FALSE/error 6 records
   `CandidateInvalidAtQuery`. Any other failure is UNKNOWN. TRUE proceeds to
   identity comparison; its flags alone never establish exclusion. The API is
   read-only and documents extended errors through `GetLastError`.
   See [GetHandleInformation](https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-gethandleinformation).
6. Compare the candidate with the still-owned reference. TRUE records
   `SameObject`. FALSE/error `ERROR_NOT_SAME_OBJECT` (1656) records `DifferentObject`.
   Every other FALSE combination is UNKNOWN, including error 0, access denied and
   error 6 after the successful validity query. Do not retry a changing candidate.
7. Close only the exact returned reference, at most once. Mark close entry before
   calling, clear the stored reference only after confirmed TRUE, and preserve
   failure/unavailable outcome without retry. No exclusion result may be emitted
   until this close is confirmed. Process teardown is not explicit close proof.

For operations whose FALSE/error pair is interpreted, clear last error to zero
before the call and capture it immediately after a FALSE return. Do not consume
stale success-path last error. An exception or uncertain call outcome can never
be converted into a known native error or successful observation.

`CompareObjectHandles` compares kernel-object identity without requiring specific
access rights. Its example documents `ERROR_NOT_SAME_OBJECT` for a mismatch across
object types. The conservative requirement for explicit 1656 on every accepted
mismatch must be checked on the supported native runner; do not broaden acceptance
to all FALSE results if an unexpected result appears.
See [CompareObjectHandles](https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-compareobjecthandles)
and Microsoft's [SDK error definitions](https://github.com/microsoft/win32metadata/blob/main/generation/WinSDK/RecompiledIdlHeaders/shared/winerror.h)
for 6, 183 and 1656.

Keep separate internal observations for acquisition, query and cleanup:
`OpenOutcome`/`OpenError`, `ProbeStage`/`ProbeOutcome`/`ProbeError`, and
`CloseOutcome`/`CloseError`. Outcome distinguishes not entered, return unavailable,
known success and known failure; nullable error is null when no error was observed.
The high-level adapter's success-path zero is only a normalized out-parameter,
not an observed last-error value; do not serialize or store it as a captured error.
Keep the identity `Reason` independently, such as DifferentObject or SameObject.
Successful cleanup cannot overwrite probe error 1656 or its reason; failed cleanup
cannot erase a known SAME_OBJECT decision. For example, different/error 1656 plus
close FALSE/error 5 retains both errors and yields semantic UNKNOWN. These fields
are internal observations only, not new JSON fields or release authority.

The semantic result is EXCLUDED only for `ReferenceAllocatedAtCandidate`,
`CandidateInvalidAtQuery` or `DifferentObject`, followed by confirmed owned close.
`SameObject` followed by confirmed close is SAME_OBJECT. Any unresolved operation,
including close, makes the semantic result UNKNOWN. Never close the candidate
even when it is the same object as the reference; those remain separate ownership
roles, and only the newly opened reference belongs to this observation owner.

## Executable native-call boundaries

Fakes of the observer's `ISentinelQueryApi` prove decisions, but cannot prove the
real adapter's clear/call/capture ordering. `NativeSentinelObservationNative.cs`
therefore defines two narrow raw-call interfaces actually consumed by that code:

- `ISentinelQueryNativeCalls`: `ClearLastError`, `CaptureLastError`, `OpenEvent`,
  `GetHandleInformation`, `CompareObjectHandles` and `CloseHandle`.
- `IFreshSentinelNativeCalls`: `ClearLastError`, `CaptureLastError`, `CreateEvent`,
  `SetHandleInformation` and `CloseHandle` for the parent's own sentinel only.

The real implementations forward to the documented P/Invokes and
`Marshal.GetLastWin32Error`; they contain no policy or alternate targets. The
child's `NativeSentinelQueryApi` takes the first boundary in an internal constructor
and executes its real ordering and fixed arguments with either real calls or a
recording managed fake. Its default construction selects only real calls. The
parent's existing owner takes the second boundary through a test-only internal
constructor overload; public runner inputs cannot select either boundary.

Extract `ChildCaptureOwner.PrepareFreshSentinel(IntPtr privateDescriptor)` from
the existing `Prepare`, and `CloseSentinel()` from the existing sentinel close.
These exact methods use the injected parent boundary; real `Prepare` and `Release`
must call them. Keep the sentinel handle and existing `sentinelClose` proof on that
same owner, not a second independent owner. Record each native entry before its
call, assign a returned handle to the rooted field before error capture, and keep
unknown acquisition/capture outcomes retained. Confirm freshness before calling
`SetHandleInformation(sentinel,1,1)`; set `SentinelReady` only after its known TRUE.
Fresh preparation itself is one-shot: consume its entry before even clearing
last error, and refuse repeats without another create or flag change. Beginning
`CloseSentinel` clears readiness, so cleanup cannot leave a launchable closed handle.

The real `Launch` must begin by refusing absent `SentinelReady` before image-file
opening, command construction, `Proof.BeforeCreate` or `CreateCalls`. A refused or
uncertain acquisition can never be converted into launch readiness by cleanup.
On error 183, no inheritance or launch occurs; cleanup can close only the returned
owned handle through the one-shot proof. Close failure or unavailable return
remains unresolved on the same rooted owner, without a second attempt from Release.

Managed tests compile the real adapter and real parent methods, inject raw-call
fakes, and inspect exact call traces. They do not call the full native `Prepare`
or a successful `Launch`, and never pass fake values to P/Invoke. Verify a refused
actual `Launch` fails at its readiness guard before any file/process operation.
Test both success/failure argument tuples and unavailable returns, rather than
asserting source text or using only a fake above the adapter. This adds no launcher
flexibility: executable, case set, event namespace and inherited handles stay fixed.

### Supported systems and inference boundary

The native adapter uses the documented Kernelbase.dll `CompareObjectHandles`
export. The test-only minimum is Windows 10 / Windows Server 2016; the existing
`windows-2022` runner meets it. Keep C# 5, x64 and .NET Framework 4.8. Unavailable
API means UNKNOWN, never fallback to `SetEvent` or an apparent passing skip.
Do not raise the production application's operating-system requirement.

The reference-allocation classification is an inference from a new handle's
exclusive live slot: opening a reference cannot replace another still-live
handle at that number. A still-live inherited sentinel must therefore be compared
as SAME_OBJECT, not accepted as this allocation case. This reasoning needs review;
the proposal does not claim a native collision test has established it. Windows
documents that handles are process-context values referring to objects:
[Handle Inheritance](https://learn.microsoft.com/en-us/windows/win32/sysinfo/handle-inheritance).

Exclusion is an observation at a query or allocation instant, not a complete
historical inheritance census. A handle closed before observation is not detected
historically. The trusted child never closes the borrowed candidate. Runtime
interference, hostile children and same-user object interference are not proved
safe. No arbitrary native collision, race or exploit demonstration is part of
verification; deterministic managed handle-table cases cover these decisions.

## PVC2 semantic byte contract

Keep the eight-byte preamble length. It is a new protocol, not fabricated old
`SetEvent` return/error bytes:

- Bytes 0..3: ASCII `PVC2`, decimal `[80,86,67,50]`.
- Byte 4: `0=UNKNOWN`, `1=EXCLUDED`, `2=SAME_OBJECT`.
- Bytes 5..6: reserved, both zero. They are not native error fields.
- Byte 7: decimal 165.

The sole passing preamble is `[80,86,67,50,1,0,0,165]`. The parent requires all eight
bytes exactly and rejects PVC1. Internal branch/error observations are not added
to the JSONL schema; successful exclusion branches normalize to this honest
semantic result. Malformed/truncated preambles and all non-EXCLUDED results mark
the parent observation UNKNOWN. This is a trusted child's report, not independent
process attestation or release authority.

Empty still writes zero bytes to both streams. It returns 0 only for completed
EXCLUDED with confirmed reference close, otherwise 94. Other cases emit the actual
semantic result, retain their fixed bodies and intended scenario exit codes.
An ordinary exception can still take the existing exit-93 path. The parent still
checks its actual original manual-reset sentinel is nonsignaled, separately from
the preamble or Empty exit inference.

Body generation, sizes and hashes remain independent of expected observations.
Only the successful stdout preamble changes. FNV-1a uses the existing offset
14695981039346656037, multiplier 1099511628211 and UInt64 wraparound. Independent
offline expectations for PVC2 plus the unchanged seed-0 body are:

- 17 body bytes, 25 total stdout bytes: `e6a7f5deb30873c0`.
- 4,097 body bytes, 4,105 total stdout bytes: `031381f5c4fbe740`.
- 196,731 body bytes, 196,739 total stdout bytes: `c1f1accadf2339e9`.
- Empty stdout/stderr, no preamble: `cbf29ce484222325`.

Stderr bodies and hashes are unchanged. These constants are offline calculations,
not Windows results. Do not calculate expected bytes from the captured preamble.
The existing pure `Expected(int length, int seed, bool header)` helper in
`NativeChildCaptureNativeTests.cs` must change its independent literal header.

## Integration and evidence preservation

Preserve Empty, Binary, Large, Nonzero, Exit259, PostCreateFault, CaptureFault,
EvidenceFault and WithheldEof, plus the three environment observation cases. All
current counts, retention bounds, fault thresholds and environment byte-8 offsets
stay unchanged. Preserve genuine exit code 259, fair dual-stream draining,
continued discard after capture faults and independent evidence-sink failure.

The child and environment JSONL schemas stay byte-for-byte the same field sets.
`sentinel_probe` now means the validated PVC2 semantic result or Empty equivalent;
`sentinel_unsignaled` remains the separate actual parent observation. Existing
parent `resources_released` and `all_owners_released` fields keep their parent-owner
meaning. They do not claim explicit child-reference release when the sentinel
probe failed. Failure artifacts remain useful diagnostics, never passing evidence.

Split implementation into a pure protocol/token/query-state component and a small
native adapter. Stage pure fake-API contracts first; only after review connect the
adapter, existing owner and fixed child. Every path compiling the child, including
the file-only image runner, must include the new dependencies. The four image
cases continue to observe files only and do not launch this child. Keep pristine
image expectation generation before negative copies; changed executable bytes
receive genuinely regenerated build expectations, not patched old hashes.

Actual Windows observations are now accepted only for the published source/tree
and runs in the [execution record](../EXECUTION-2026-11-11-native-sentinel-observation.md).
Both native runs passed the unchanged 9+3+4 assertions and strict validators.
The normalized PVC2 result does not expose which exclusion branch ran or establish
native error-1656 coverage. Those distinctions remain deterministic managed-model
and raw-call-fake coverage, not an actual collision/race experiment. The b2229c5
failure remains unchanged and separate. No assertions were weakened, collisions
manufactured, retries added, timeouts raised or failed CI rerun to obtain green.
No production safety or release claim follows.
