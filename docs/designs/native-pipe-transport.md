# Test-only bounded native pipe transport

## Boundary and choice

This transport-only experiment adds two
owned, preconnected, private byte-mode named-pipe pairs and finite in-process
overlapped producers. It never launches a child or requests elevation. No
VirtualBox, service, PnP, environment block, handle inheritance, bootstrap,
admission, retry, recovery or production integration belongs to this increment.
The preceding no-pipe launch observer remains unchanged.

Anonymous `CreatePipe` cannot provide overlapped I/O. Blocking reader threads
would introduce a second unresolved lifetime. `PIPE_NOWAIT` and `PeekNamedPipe`
are not substitutes for overlapped completion. The selected experiment uses
first-instance, one-instance named pipes with generated names, byte mode,
remote-client rejection and a DACL restricted to the current identity and SYSTEM.
Both endpoints belong to the same test process. Names are never external inputs
and are not ownership proof or production privileged ACL acceptance.

## Lifetimes and bounds

Each read, write and connect slot has its own manual-reset event, stable unmanaged
OVERLAPPED and preallocated 4 KiB buffer. Slots are rooted before submission.
Preparation itself is one-shot before the first allocation/native call. A partial
setup failure cannot retry and overwrite already owned slots or handles.
Submission enters potentially-live state before the native call. A genuinely
unavailable submission result is irreversibly retained in this experiment: even
an apparently successful query of zero/stale OVERLAPPED fields cannot cure it.
For a known submission, only a documented synchronous result or the current
operation generation's terminal `GetOverlappedResult` permits reuse and release.
FALSE with `ERROR_IO_PENDING` is pending, not terminal. Signals, timeouts, failed waits, cancellation requests and
`ERROR_NOT_FOUND` do not. Unknown submission/results retain storage and fail the
run. No finalizer, counter, exported handle count or empty status can release it.

One bounded owner loop visits both readers and both finite producers every round.
Each visit performs at most one completion and one submission. Retained output
is preallocated to 64 KiB per stream. Beyond capacity or an injected diagnostic
fault, reads continue into the same buffer and discard without allocating.
Observed bytes, a streaming FNV-1a-64 byte hash, retained bytes and discarded bytes remain
separate. UNKNOWN is sticky and does not prevent release after actual completion.
The hash is only an accidental data-integrity checker, never ownership,
authentication or tamper-resistance proof. Fairness is measured by per-round
visits as well as completed byte counts.
EOF is a distinct terminal pipe result, never an empty read or expired budget.
Only `ERROR_BROKEN_PIPE` (109) is clean EOF for these owned PIPE_WAIT byte pipes.
`ERROR_NO_DATA` (232) can be terminal I/O but stops that reader with UNKNOWN,
without claiming EOF. An EOF-budget expiry remains UNKNOWN after later actual EOF.

Finite producers write fixed binary patterns larger than pipe and retention
capacity on both channels. A separate bounded warm-up issues no reads and must
actually observe `ERROR_IO_PENDING` writes and repeated exact
`GetOverlappedResult` / `ERROR_IO_INCOMPLETE` results on both pipes across at least
10 ms without readers before fair draining. Historical pending returns alone are
insufficient. Completed writes are harvested and finite filling continues, with
a 16-write-per-channel and two-second warm-up bound. Unknown query failures do
not count as incomplete results.
Separate cases prefill for immediate reads, issue
empty reads for genuinely pending I/O, deliberately keep a duplicate writer open,
cancel at several completion boundaries, and fail one stream while the other
drains. Injected submission/wait/diagnostic cases are labeled managed or injected;
they do not claim a persistent real WAIT_FAILED or actual allocation failure.
The loop avoids per-reissue struct boxing by writing a verified x64 OVERLAPPED
layout into the same unmanaged storage. This is not a claim of OOM-proof .NET or
kernel behavior. A per-handle close-attempt record is set before every close,
including original and duplicate writers closed during the loop. Unavailable or
known-FALSE close returns cannot be retried against a possibly stale numeric
handle and cannot produce a successful release receipt.

## Evidence and failure

All reports have `mutation_authorized=false`; there is no report input/resume
interface. JSONL reports are fixed-schema, strict UTF-8 and bounded before writes.
The main loop has a finite three-second budget and cancellation draining has a
separate two-second budget. The runner preserves generated files if any rooted
operation lacks verified terminal completion. A safe-to-release receipt is
emitted only by a traversal of actual fixture owners, including setup/connect
state, separate duplicate writers and successful handle closes, never a missed
unresolved counter. Process teardown
does not count as explicit cancellation. Artifacts contain bounded text only.

Linux runs the managed decisions and explicitly skips native claims. Windows
compiles C# 5 / x64 / .NET Framework 4.8. Success requires actual native calls,
terminal producer operations, fair reader progress, exact byte counts/hashes and
safe fixture release. A setup failure cannot skip the positive assertions.
The artifact is `native-pipe-transport-text-only`, containing only
`native-pipe-transport.jsonl` (at most 64 records, 4 KiB per record and 256 KiB in
total). Generated executables, buffers and diagnostic-fault files are not
uploaded. Reports use fixed field names and bounded numeric values; the runner
streams them, checks bounds before UTF-8 allocation, and validates strict JSON
including failure records before artifact copying.

## Observed source checkpoint

Source `c42ce9791925c40dce5c9b6e987a125515eaa3aa` passed the Windows
native push job on attempt 1. The PR native job also passed on attempt 1, but
checked out synthetic merge `5a1e6f2f4d94a318e05c45e1214a7626b8560f2a`,
not the source commit directly. Independent final review accepted 85
managed checks, 14 native cases and 573 separate native/harness checks, with
actual backpressure on both pipes, bounded capture/discard, fair draining,
sticky UNKNOWN and explicit fixture release. Both cancellation-race runs
observed completion winning (1168/0); the abort-winning race branch remains
unobserved, although separate pending-read cancellations returned 995.

Unknown submission, uncertain close, stale generation, error 232 and
partial-setup decisions remain managed negative tests, not induced native
faults. See the [execution record, digests and limits](../EXECUTION-2026-11-11-pipe-transport-and-messages.md).

## Still blocked

This does not prove synchronous inherited child writers, repair
`SessionHelper.Main`'s Process.Start/capture/wait lifetime gap, or establish
environment/STARTUPINFOEX/admission/lineage/SCM/PnP authority. In particular,
`scripts/privileged_session_worker.ps1:78` starts VBoxSDS before the try/handle
boundary at lines 79–80. Outer-helper work cannot certify descendants. No
power-loss, UAC, workstation or VM-release readiness follows from this fixture.

## References

- https://learn.microsoft.com/en-us/windows/win32/ipc/anonymous-pipe-operations
- https://learn.microsoft.com/en-us/windows/win32/ipc/synchronous-and-overlapped-input-and-output
- https://learn.microsoft.com/en-us/windows/win32/api/ioapiset/nf-ioapiset-getoverlappedresult
- https://learn.microsoft.com/en-us/windows/win32/api/ioapiset/nf-ioapiset-cancelioex
- https://learn.microsoft.com/en-us/windows/win32/api/namedpipeapi/nf-namedpipeapi-connectnamedpipe
- https://learn.microsoft.com/en-us/windows/win32/api/namedpipeapi/nf-namedpipeapi-peeknamedpipe
