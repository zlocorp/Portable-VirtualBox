# Test-only fixed-child capture

This increment composes exact original process/thread ownership with the earlier
unchanged overlapped read slots. It launches only the compiled sibling
NativeCaptureFixtureChild.exe with fixed case names and a diagnostic sentinel
handle number and generated fixed-name token. No user executable, argument,
environment, report or recovery input is accepted. No VBox, elevation, services, drivers, network or descendants exist
in the fixture. This is not production launch or environment/descendant safety.

## Approach

Use two private byte-mode named pipes, preconnected synchronous inheritable child
writers, and overlapped noninheritable parent readers. Anonymous pipes cannot
provide this asynchronous parent API; blocking reader threads add another lifetime.
Reuse PipeCapture, PipeOperationProof, PipeCloseProof and PipeNativeSlot without
editing their existing files. STARTUPINFOEX's handle list contains exactly stdin
NUL and the two writers. An unrelated inheritable event is excluded from the list.
The parent creates it fresh in the fixed token-derived namespace with the existing private DACL, refuses
an existing object before inheritance changes, and retains its original handle.
The child opens a noninheritable SYNCHRONIZE-only reference and uses query-only
handle identity observation, then confirms closing only that owned reference.
Its PVC2 semantic preamble reports EXCLUDED, SAME_OBJECT or UNKNOWN. Only exact
EXCLUDED passes. The parent independently checks its original sentinel is
unsignaled. This is an instant query/allocation observation, not a historical
inheritance census or production safety claim. See the
[exact sentinel design](native-sentinel-observation.md) for ownership, error 1656,
allocation-at-candidate inference and unresolved-close limits. The test-only
comparison API requires Windows 10 / Server 2016; production support is unchanged.

All owner objects and operation buffers are rooted before CreateProcessW. Native
PROCESS_INFORMATION is written directly into the owner's field; original handles
are never reopened by PID. Exit requires a signaled exact process handle before
reading the exit code; 259 is a valid fixture exit code. Both EOFs, all exact I/O
terminal results and individually confirmed closes are independent facts.
Unknown native call outcomes retain owners. Cancellation alone cannot release.

The child uses synchronous WriteFile and finite fixed binary output. The parent
visits each reader once per round, alternating order, retaining at most 64 KiB per
stream and draining/discarding beyond it. Injected post-create, capture and evidence
faults make UNKNOWN sticky but draining continues. A retained duplicate stdout
writer demonstrates child exit without stdout EOF, then closes and permits EOF.
Cases are Empty, Binary, Large, Nonzero, Exit259, PostCreateFault, CaptureFault,
EvidenceFault and WithheldEof. Empty writes zero bytes to both streams: its fixed
child returns 0 only after completed EXCLUDED with confirmed owned-reference close,
otherwise 94. The parent infers that result from this exact observed exit code and
separately checks its sentinel remains unsignaled. Other cases carry a fixed
8-byte PVC2 semantic preamble on stdout. This fixed-fixture exit inference
is not production child identity or general inheritance proof. Each case has a two-second pump budget
and bounded cancellation recovery; healthy total native run target is under 20 s.

Environment is inherited unchanged via a null environment pointer. The fixture
reads no environment-selected commands or behavior. This deliberately does not
prove a sanitized production environment or malicious-child containment. Images
are fixed sibling build outputs held read-only without write/delete sharing.

Reports are bounded strict JSONL, text only, always mutation_authorized=false.
Fixture expectations (pattern lengths/hashes and intended exit codes) are checked
against separately recorded OS observations, never substituted for them. Reports
and counts authorize no release. Unresolved owners stay rooted until harness exit;
OS process teardown is not claimed as successful explicit release.

## Observation review

`status=PASS` means the test's assertions held, including expected UNKNOWN faults;
it is never a successful production launch/admission signal. `fault_site` identifies
the injection actually reached, and `evidence_bytes_written=1` means the controlled
one-byte Write returned before the injected exception, not that a durable flush
succeeded. Native call counts, exact wait/exit observations, per-stream byte hashes,
retained/discarded totals, operation counts and fair visits are diagnostics only.
`create_error` is captured only from a known FALSE return; successful creates emit
zero instead of an unrelated stale last-error. `assertion_failed_at` identifies the
numbered assertion in AssertCase (or -1 for an exception before assertions).

Native submission-unknown, persistent wait failure, arbitrary allocation failure,
malicious children, loader/environment interference and descendant containment
are not claimed as exercised OS cases. Managed decisions and fail-closed source
paths cover the first limitations; this fixture cannot establish production safety.

## Current sentinel composition

The pure sentinel contract passed independent source/interface review. The native
adapter, fresh-parent owner composition and fixed-child PVC2 output are implemented
locally with managed behavioral tests. Independent Task 2 review and changed-source
Windows observation are pending. These local tests are not native evidence and do
not reclassify the preserved b2229c5 PR failure or the historical checkpoint below.
Both JSONL field sets, all nine case purposes and all exit/EOF/release assertions
remain unchanged. `sentinel_probe` now means exact PVC2 EXCLUDED or Empty's dedicated
exit inference; a failed probe cannot claim explicit child-reference close.

## Observed checkpoint

Independent review accepted the exact-source push and synthetic-merge PR native
observations for source `50262c86658ce99453845a021786b781d68aae87`: all nine
cases completed with the stated byte/hash, fault, exit/EOF and release facts.
The [execution record](../EXECUTION-2026-11-11-fixed-child-capture.md) distinguishes
tested checkout revisions and preserves digests, all 11 successful workflow runs
and remaining limits. This does not broaden the test-only boundary above.
