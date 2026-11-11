# Native pipe transport implementation plan

**Goal:** Prove bounded, fair file/IPC-only draining and exact terminal I/O
completion before native storage release.

**Architecture:** Two preconnected owned named pipes, six preallocated operation
slots, one finite fair owner loop and independent capture/completion facts.

**Tech Stack:** C# 5, x64 .NET Framework 4.8, PowerShell, Python unittest.

**Spec:** `docs/designs/native-pipe-transport.md`; transport-only scope A is binding.

## Global constraints

- No production source/scripts, existing observer, build/package changes.
- No child process, inherited handles, arbitrary inputs, elevation or VBox.
- 4 KiB slot buffers, 64 KiB retained per stream, fixed finite producers.
- No cleanup based on signals, cancellation success, zero handles or counters.
- C# 5; no new dependencies; observations never authorize mutation.
- Existing native job permissions and six-minute budget remain unchanged.

## Review focus

- Partial setup exceptions: every issued slot remains rooted until terminal.
- Completion races: event/cancel result never substitutes for exact I/O result.
- Output faults: both streams drain after capture is UNKNOWN.
- Failure reporting: finite strict UTF-8 JSON is valid even for failed cases.
- Cleanup exceptions: a missed counter cannot issue a release receipt.

## Task 1: Managed decisions and bounded capture

Files: `tests/windows/NativePipeTransport.cs`,
`tests/windows/NativePipeTransportTests.cs`,
`tests/windows/check_native_pipe_transport.ps1`,
`tests/test_native_pipe_transport_contract.py`.

Interfaces: `PipeOperationProof` records issued/terminal state;
`PipeCapture` retains and hashes bytes; `NativePipeTransportTests.RunManaged()`
returns a strict JSON summary. All types are test-only.

- [x] Write executable lifetime, cancellation, fault, binary and retention tests.
- [x] Witness RED against deliberately incomplete decision/capture implementation.
- [x] Implement exact completion release eligibility and preallocated capture.
- [x] Run focused tests and the full Python suite to GREEN.

## Task 2: Owned native transport

Files: `tests/windows/NativePipeTransportNative.cs`,
`tests/windows/NativePipeTransportNativeTests.cs` plus runner.

Interfaces: `PipeFixture` owns all preallocated `PipeNativeSlot` objects;
`Run` is single-consumption; `DrainCancellation` obtains exact completions;
`SafeToRelease` traverses actual slot state. No serialized inputs.

- [x] Write native scenario assertions before native implementation.
- [x] Compile C# 5 against existing official net48 references; Linux explicitly skips native execution.
- [x] Implement owned pairs and bounded fair loop, keeping storage on unknown.
- [ ] Exercise immediate/pending/binary/large/fair/fault/cancel/EOF/error cases.
- [x] Run managed regression and full suite; Windows native result remains pending CI.

## Task 3: Evidence and integration

Files: runner, Python contracts, this plan and design,
`.github/workflows/native-tests.yml` only.

- [x] Bound JSONL generation, strict UTF-8 validation and artifact copy before allocation.
- [x] Add one file/IPC-only native step and explicitly text-only artifact/path filters.
- [ ] Run full suite, source audit and independent review; report limitations.
- [ ] Obtain independent review before committing or publishing.

## Execution ledger

- Initial HEAD: `e227a473c237f5d9d7f900d7242aca7031a02917`, clean.
- Scope: use the existing development checkout; no unrelated files edited.
- Managed RED witnessed: the compiled test failed at check 2, "Issuing must root
  storage BEFORE the call returns". The incomplete scaffold initially had unused
  field warnings; those were corrected before counting the behavioral RED.
- Review correction RED witnessed: unavailable submission was incorrectly allowed
  to become releasable (check 13). It now irreversibly retains storage. A second
  RED at check 15 rejected stale generation completion before the generation
  guard was implemented. Known pending operations remain eligible for actual
  later completion, independently of sticky UNKNOWN.
- First full portable suite: 320 tests total, OK, 6 platform skips.
- Additional witnessed REDs: unobserved/failed per-handle close could appear
  releasable (check 18), error 232 incorrectly meant EOF (check 24), EOF budget
  expiry lacked sticky UNKNOWN (check 25). All three then passed.
- Strict-evidence REDs rejected permissive mutation authority, oversized lines
  and total artifacts, empty files and non-object records after implementation.
- Current local verification: 85 managed checks; four focused Python contracts;
  full repository suite 324 tests total, OK, 6 platform skips; C# 5/x64/net48 compilation
  with warnings as errors; active-tree and whitespace checks passed.
- Fourteen native cases are written but have NOT executed on Linux. Pending
  writes, native cancellation races and actual EOF remain Windows CI gates.
- Additional close-proof RED at check 22: a second reported success could
  replace a known FALSE close. Return evidence is now consumed once, and the
  rejected replacement keeps the owner unresolved.
- Final review correction: backpressure needs repeated exact IO_INCOMPLETE
  queries on both current writes, not historical IO_PENDING returns. The bounded
  no-reader observation now lasts at least 10 ms, harvests any completed writes,
  and fails on unknown query outcomes. Actual execution remains a Windows gate.
- Partial-setup regression RED at check 1: preparation was not consumed before
  allocation. The shared guard now records the first attempt irreversibly and
  rejects re-entry even when setup-complete and run-consumed fields remain false.
- Cancellation-race assertions skip full byte/hash/EOF checks only for actual
  ERROR_OPERATION_ABORTED. A completed read when cancellation loses must satisfy
  the normal complete-capture assertions.
