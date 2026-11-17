# Checkpoint before cleanup diagnostics: hosted execution record

Date: 2026-11-11. Tested runtime/source commit:
`175e6a43f31d71a28d218c744dae7d34fd378680`.
All **14 triggered workflow runs passed on attempt 1**. Independent actual-diff
and final artifact review accepted this narrow hosted increment. This is **not
release approval**. No primary/user Windows host, merge or release was involved.
The [previous b9db2b0 record](EXECUTION-2026-11-11-payload-cleanup.md) remains
historical evidence for that checkpoint only.

## Implemented boundary

The private `CompleteCleanupWorker` now persists and verifies `WorkerExited`,
drains both output-capture tasks, checks the worker result, deadline and exact
live controller, and performs the existing receipt/ownership/system verification.
Only then does it create and reread the durable private-payload checkpoint,
**before** the mandatory stdout, stderr and facts writes. Prepare is unchanged.

A failure still returns 70 and blocks private deletion. Diagnostic failure does
not replace an earlier worker/checkpoint rejection. A later explicit Finish or
Recover may use an intact checkpoint only to continue already-verified private
app64/code deletion. It cannot recreate payload, rerun the worker or repeat a
system operation. Original object identities, leases, ownership checks and the
deletion journal remain required. Missing or uncertain evidence still refuses
continuation. See the [implementation plan](plans/2026-11-11-checkpoint-before-diagnostics.md).

This narrows the successful-teardown/diagnostic-write gap; a capture failure or
crash before checkpoint durability remains unsupported. General SDS/SCM/PnP retry
is not implemented. The separate [system-outcomes model](designs/system-cleanup-outcomes.md)
is test-only: every result has `mutation_authorized=false`, and its no-launch,
lineage and postcondition premises are supplied theoretical inputs, not
authenticated Windows evidence or authority.

## Exact-commit workflow results

All runs below succeeded on the full source SHA above:

- Native Windows regressions [43018813929](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43018813929)
  and [43018821104](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43018821104):
  33 AutoIt harnesses; CLI 44, durable attempt journal 706, package identity 28,
  payload journal 3,310, fixed plan 854, native object 25, integrated owner 141
  and cleanup completion 464 assertions, plus start gates and failed-stopped checks.
- [Private payload continuation, 43018813937](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43018813937):
  all nine controlled cases passed; job `130516534702`'s runtime verification
  step completed in 8m 32s.
- [Fixed helper, 43018813715](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43018813715):
  both session-test and main-launcher jobs passed. The latter proves medium-token
  Manager/guest, protected-write denials, guest VDI readback, snapshot preservation
  and two cycles. This is the helper-boundary evidence, not the legacy Manager fixture.
- [Orphan recovery, 43018813663](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43018813663)
  and [interrupted preparation, 43018813895](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43018813895)
  passed; all three interrupted-preparation jobs succeeded.
- [Russian Oracle and Alpine, 43018813769](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43018813769):
  real Russian first start/reopen and English second start, guest VDI readback,
  snapshots, two cycles and rebind passed. This already-elevated/legacy Manager
  fixture is UI/guest evidence, not proof of the fixed-helper privilege boundary.
- [Relocation, 43018813669](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43018813669):
  all four powered-off directory/drive-letter relocation jobs passed.
- [Noninteractive pending UAC, 43018813852](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43018813852),
  [ALPHA build/server refusal, 43018813655](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43018813655),
  [Oracle file-only preparation, 43018821198](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43018821198),
  builds [43018820998](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43018820998)
  and [43018813634](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43018813634),
  and [source snapshot, 43018813682](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43018813682)
  passed.

These are the 14 triggered runs, not every workflow in the repository. The
relocation and Manager workflows now trigger when their existing extraction
dependencies change; their execution commands are unchanged. The Manager
workflow also has a unique display name. Earlier
failures are not retroactively counted as successes.

## Nine payload-continuation cases

The hosted fixture retains AfterFirstDelete -> Finish and BeforeMarker -> Recover.
It adds BeforeStdout, BeforeStderr and BeforeFacts after an initial Finish, each
followed by explicit Finish or Recover. The ninth case,
`BeforeFacts-Recover-InitialRecover`, closes the original owner, faults the initial
Recover, then resumes Recover from the **same live recovery initiator**. It does
not test takeover by a third controller.

Each diagnostic-failure case proved code 70, a valid checkpoint, every private
payload path/hash unchanged and no deletion journal or terminal marker yet. Its
explicit continuation preserved acquisition/cleanup evidence and VM sentinel
data, without payload recreation or a second worker/system operation. The hooks
throw immediately before the respective writes; the managed sequencing tests
also exercise actual write-operation exceptions. The exact-commit proof lists
all nine completed cases and reports unchanged cleanup evidence, no payload
recreation, preserved original VM data and removal of all owned services.
This fixture does not boot a guest and does not exercise interactive UAC.

Independent review reconciled all nine sessions: 220 original identities and a
valid 441-event BEGIN/DONE/COMPLETE chain each. Checkpoint hashes match the
original worker journal and stage/cleanup receipts. Continuation created no new
helper evidence. All seven diagnostic cases preserve their deliberate missing
diagnostic and controlled failure. The ninth case separately binds the original
owner and recovery initiator; the same initiator continues.

Archived baseline files match their preserved hashes. The collector omits four
stage/start stdout/stderr files named in the preserved hash maps: their equality
was asserted on the runner, but their bytes cannot be independently compared
from the downloaded archive. This record does not claim every baseline byte was
checked offline.

## Retained evidence identities and visual checks

Downloaded archives were verified against their artifact SHA-256. Preserve the
archives with their exact-commit proof records before a future candidate decision;
temporary GitHub artifacts and green badges are not a permanent evidence store.

- Payload artifact `13854990941`, `payload-cleanup-recovery-evidence`:
  `28e8a42c99a47d688f3809d81c6db936fb7715f7f72690d271b48bc5f117ade2`.
  Exact-SHA proof and nine-case results described above; expires
  2026-11-18 at 12:25 UTC.
- Launcher artifact `13853966953`:
  `9ff901233e14310a0bf37e245343366cac2d33440af5ef167c7bb4e6c66f4320`.
  RU/EN/RU screenshots were inspected at the runner's DPI; the returned Russian
  image is byte-identical. This is not 100%/150%/200% scaling acceptance.
- Oracle/Alpine artifact `13854381528`:
  `d16b34e164546efa1222183d2e9728adf1500fc3b7d7b6a69daa5729dd54452d`.
  Proof names the exact source SHA and records Russian start/reopen, English start,
  VDI/snapshot, two cycles and rebind. Native Oracle-window PNGs were inspected:
  real Russian/English captions are visible, and Oracle's unsupported USB
  enumeration notification remains visible. No warning-free UI or USB support
  is claimed.
- Main-launcher fixed-helper artifact `13854092282`:
  `aa47adec37894ebe15f37e924959112b50fcd1d8ed59d958f7bd2fd989e87eaa`.
  Exact-SHA proof records the medium-token Manager/guest boundary, protected
  denials, VDI readback, snapshot and two cycles. Deny-write 2/3 stdout reports
  `PROTECTED_CACHE_DENIALS=12`. GUI runas and interactive UAC are false/unverified;
  a direct-elevated test invoker was used.

## Local gates and remaining release blockers

Local source suite: 313 tests run, OK, with six platform-specific skips. The real
private sequencing method passed 464 managed assertions across 52 cases, including
double faults; restoring the old checkpoint-after-diagnostics ordering was
rejected by mutation testing. Helper and fixtures compile in C# 5 against
.NET Framework 4.8 reference assemblies. Independent actual-diff and final artifact
review accepted this scope, including the artifact digests and two observed
`PROTECTED_CACHE_DENIALS=12` results.

General system-effect retry, isolated interactive Windows 10/11 UAC,
100%/150%/200% UI scaling, final candidate packaging/host acceptance and physical
power-loss recovery remain open. Primary-OS safety is not certified. Complete
active/incomplete sessions with their original paired frontend/helper before
upgrading; never remove or rebuild protected evidence to bypass a mismatch.
See the [release gates](RELEASE-GATES.md).
