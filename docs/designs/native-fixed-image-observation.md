# Test-only fixed-image observation and preflight

## Status and boundary

Task 1 is accepted as a test-only file-observation stage at source
`33447ae2ff048230675c05c72509857d252fceee`. Independent review verified actual
native PR observations at synthetic merge
`7f66505650b282efcff8fb08841619c03ec9211b`, whose tree equals the published tree
`b88bc27ebaf4693571e3f3505c6d3404962d7ab3`: all four image cases, nine baseline
cases and three environment cases passed. Both Linux jobs also passed real
pinned-reference provisioning and 392 tests with six unchanged platform skips.
All five naturally triggered workflows passed on attempt 1; there is no native
PUSH run for this source. See the [successor execution record](../EXECUTION-2026-11-11-net48-reference-provisioning.md).

The earlier `b2229c5` [partial checkpoint](../EXECUTION-2026-11-11-native-fixed-image-file-only.md)
retains its eight successes and three failures. At that historical checkpoint Task 2 required separate composition review and
hardening of the numeric sentinel diagnostic limitation. Task 2 remains
unimplemented. Meeting the file-only prerequisite does not authorize composition
or establish whole-product readiness.

The successor query-only sentinel source `519056432b4d9bd045140d2ba2bbe924e5c135e9`
(tree `45d21240a2b93e79f69b7a0c415d34ed7acdd31f`) now has independently
accepted actual native push run [43101335942](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101335942)
and same-tree PR run [43101344284](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101344284).
Each preserved all nine capture, three environment and four file-only image cases.
Both hosted Linux jobs ran 403 tests with six unchanged platform skips. The final
independently reconciled inventory has all eleven workflows successful on attempt 1
(eight push, three PR), including private-payload continuation run 43101335826.
The [sentinel execution record](../EXECUTION-2026-11-11-native-sentinel-observation.md)
was committed locally as `31255f3`; the published tested source remains `5190564`.
Earlier source/run records remain unchanged. The changed-source native prerequisite
is satisfied; composition preflight review and the controller's next implementation
assignment remain required. Existing user authorization covers local test-only
checked-branch development without renewed user permission. This revision is
planning only, not the implementation assignment.

This is fixed-fixture observation and preflight, not privileged image admission.
Use only owned temporary files and the existing harmless sibling child. No
production changes, signatures, elevation, drivers, services, security settings,
user's Windows experiments, merge or release. Preserve the nine baseline cases,
three environment cases, their assertions and their separate evidence schemas.

## Approaches and recommendation

1. Own an exact native file handle and hash through bounded synchronous ReadFile
   calls. This adds a small read loop but makes entry, return and close evidence
   explicit. Recommended.
2. Own the same native handle and hash through a FileStream borrowing a
   SafeFileHandle with ownsHandle=false. Dispose the borrowed stream/wrapper before
   explicit native close. This reuses managed hashing I/O but adds borrowing and
   disposal states that cannot prove native close.

Both extend ChildCaptureOwner with one sealed, opt-in context; neither duplicates
its launcher. Existing FileStream.Dispose evidence remains managed disposal only.
Do not silently strengthen baseline native-close claims.

## Build provenance and closed entry

The dependency graph is acyclic and child-first, including managed-only builds:

1. Create a fresh private build root. Compile `NativeCaptureFixtureChild.exe` from
   exactly `NativeCaptureFixtureChild.cs`, `NativeLaunchEnvironmentObservation.cs`,
   `NativeSentinelObservation.cs`, `NativeSentinelObservationNative.cs`. No owner,
   test, image, generated-expectation or composition source belongs in this child.
2. After the compiler has completed and closed the output, read those pristine
   bytes, require positive length <=16 MiB, hash them, and emit
   `FixedFixtureBuildExpectation.g.cs` in that root. Preserve child/config/source
   and the generated source's checksum. Use the existing deterministic fixed syntax,
   fixed sibling filename, positive length and 64 lowercase SHA-256 characters,
   bounded to 2 KiB. This does not assert reproducible compiler output.
3. Compile every owner consumer with that real generated source and the image/
   composition sources. Verify the expectation checksum before each compilation.
   For each legacy native harness, place the unchanged fixed child and its config
   beside the harness executable, copied from the verified PristineChild output;
   recheck copied bytes against the embedded pristine length/hash before execution.
   The pristine build directory alone is not the legacy Launch sibling directory.
   Finish all four case-harness builds before making any negative child copies;
   verify the checksum again after negative setup. Never regenerate at runtime or
   after mutation, reuse a stale directory, or substitute placeholder constants.

Implement the common build operations in `tests/windows/NativeFixedFixtureBuild.ps1`:
`New-FixedFixtureBuild([string]$Parent)` returns a build record with `Root`,
`PristineChild`, `ExpectationSource`, `ExpectationSha256`;
`Assert-FixedFixtureBuild($Build)` verifies the retained expectation and pristine
bytes; `Get-FixedFixtureConsumerSources($Build,[string[]]$Names)` returns resolved
existing consumer source paths plus the checked generated source, without globbing.
`Parent` is a runner-owned temporary directory, never a harness execution selector.
The helper uses C# 5/x64/warnings-as-errors and net48 targeting: Windows csc for
Windows runs, the existing Roslyn/explicit official net48-reference route for
non-Windows managed-only builds. Compiling a net48 executable on Linux is not
executing Windows .NET Framework. Managed-only builds do not execute the child or
prepare mutated copies. Load compiled consumer assemblies for managed tests only.
When this helper dependency is introduced in 2A, immediately add the narrow
`tests/windows/NativeFixedFixtureBuild.ps1` push-path trigger to
`.github/workflows/native-tests.yml`; do not defer that dependency trigger to 2E.

Every entry below must use the child-first helper before its first owner compile:

| Entry at 5190564 | Consumer and required change |
| --- | --- |
| `check_native_child_capture.ps1` | `Invoke-ManagedContracts` Add-Type and native csc harness; move build before Add-Type, including `-ManagedOnly`. |
| `check_native_launch_environment.ps1` | Managed Add-Type and native csc harness; same ordering, preserve its full environment source list. |
| `check_native_fixed_image_observation.ps1` | Existing child-first `Compile-Fixed`, all four case harnesses and managed assembly load; reuse helper, keep pristine expectation before mutation. |
| `test_native_child_capture_contract.py`, `run_native_sentinel_contract` (588ff) | Direct owner Add-Type for real sentinel adapter/parent tests. |
| Same module, `test_native_report_serializer_matches_schema_without_native_calls` (693ff) | Direct owner Add-Type for the old serializer. |
| `test_native_launch_environment_contract.py`, `test_legacy_constructor_rejects_appended_mode_before_native_entry` (25ff) | Direct owner Add-Type for closed constructor tests. |
| Same module, `test_actual_native_serializer_emits_valid_failure_diagnostics` (414ff) | Direct owner/environment Add-Type for the old serializer. |
| New composition managed tests and composed runner | Same helper and generated-source dependency; no private alternate build recipe. |

Update source-list assertions in `SentinelSourceWiringContract` and all four direct
scripts together. `run_sentinel_contract` (pure parser/protocol/observer sources),
`test_actual_child_output_is_empty_or_exact_pvc2_and_keeps_observer_root` (the four
child sources plus its managed output harness), and the independent launch/pipe
runners do not compile `ChildCaptureOwner` or the image owner. Keep them independent;
the direct child-output compilation must still use exactly the four runtime child
sources. Python fixed-image managed coverage invokes the image runner rather than
another compiler. CI's Python discovery and native workflow invoke these entries;
there is no additional owner compilation hidden in the production compile job.
Re-run a source-consumer inventory before implementation review to catch additions.

At runtime expectations come only from embedded constants. No native entry accepts
an external path, digest, manifest, command, case or environment-selected executable.
The evidence directory never selects execution inputs.

## Exclusive image transfer and launch binding

`FixedFixtureImage.CreateForObservation()` returns a sealed unopened facade. Add an
explicit use state, separate from `FixedImageState.Released`: `Fresh`,
`StandaloneUsed`, `Claimed`. Every standalone preparation, probe or release attempt
irreversibly leaves Fresh, including a release attempt before any open. Reading a
snapshot is not use. Serialize use/claim transitions with one private lock, so two
constructors or a simultaneous standalone preparation cannot both succeed.

`ChildCaptureOwner(FixedFixtureImage image)` delegates to the same implementation
as internal `ChildCaptureOwner(FixedFixtureImage image,
FixedImageCompositionBindings bindings)` with the native bindings. That constructor
rejects null/domain mismatch, selects only existing `CaptureCase.Binary`, initializes
managed fields, then makes its last construction step `image.ClaimForComposition()`. Claim validates Fresh and unprepared/unopened
state, creates and permanently registers exactly one sealed nested
`FixedFixtureImage.CompositionLease`, and returns it for the owner's private readonly
field. No native calls occur in a constructor. A losing/invalid claim changes no
other owner's state. There is no unclaim, reset, rebind or transfer-back operation.
Prepared, independently released, previously claimed and completed contexts reject
before native setup. Original facade mutators throw after claim, even if the lease
later releases successfully. A retained caller reference can only read snapshots;
it cannot prepare, probe or close the transferred image.

The lease exposes only internal `PrepareOnce()`, `ObserveSharing()`, `Ready`,
`Released`, immutable observations, `BindBinaryLaunch(long candidate,string token)`
and `TryRelease()`. Its constructor validates a private owner key/current-lease
identity; callers cannot mint a valid lease. `BindBinaryLaunch` returns a sealed
nested `FixedImageLaunchBinding` constructed from that image context only, never
from path strings. Only the existing Launch method consumes its internal
application/directory/command properties. This is an internal fixed launch DTO,
not a public path API; it exposes no file handle, accepts no executable path and
has no mutable path setters. Validate the sentinel candidate/token with the existing
fixed Binary argument rules. At 5190564 the legacy command construction is inline,
not already shared. Task 2D extracts it once into `FixedFixtureCommand.Format(string
image,string scenario,long candidate,string token) -> StringBuilder` in
`tests/windows/NativeFixedFixtureCommand.cs`, preserving existing quotes, spaces,
scenario spelling, invariant decimal candidate and token bytes. Both legacy Launch
and the new lease binding then call that one formatter. Task 2C implements only
lease ownership/preparation/probe/release; defer `BindBinaryLaunch` and
`FixedImageLaunchBinding` implementation to 2D after the shared extraction. Do not
add a temporary duplicate formatter in 2C. All image/owner consumers gain the pure
formatter source in 2D; the four-source child stays independent. Legacy constructors
and command bytes remain unchanged. The composed branch must not acquire `imageLease` as
well: the exact native image owner is its sole image lease.

Both facade and lease use the same private preparation/probe/release implementations.
`Ready` requires the correct live use mode, completed matching observation, known
open success, image close not entered, and no unresolved file/probe operation.
Closing or an unknown return revokes readiness permanently; cached digest agreement
cannot keep Ready true. Before create, both sharing probes must also have actual
known denial/error 32. The image context owns both probe objects and their exact
handles; the owner owns the entire image context through its lease.

A composed harness roots its image and owner before `Run` and retains both through
reporting/harness exit. Only `ChildCaptureOwner.Release` calls the transferred
lease's `TryRelease`. Do not copy Task 1's unconditional `finally root.TryRelease()`
into the composed harness. No report, harness exit code or finalizer releases it.

## Exact held-file observations

- CreateFileW: GENERIC_READ, FILE_SHARE_READ only, OPEN_EXISTING, null security
  attributes (non-inheritable), FILE_FLAG_OPEN_REPARSE_POINT, synchronous I/O.
  Reject directory/reparse leaves using GetFileInformationByHandleEx with
  FileAttributeTagInfo. Ancestors remain unvalidated.
- GetFileSizeEx: positive size, at most 16 MiB, equal to generated expected length.
- ReadFile: chunks at most 64 KiB; checked cumulative count bounded by 16 MiB;
  require exactly expected bytes, then a positive-length terminal request (one
  byte) returning TRUE with zero bytes. This extra request is required even at the
  exact 16 MiB boundary; a zero-length request never proves EOF. A returned extra
  byte rejects the image without hashing it or increasing the accepted byte bound.
  Hash accepted bytes with SHA-256. Read error, impossible byte count or incomplete observation
  never constitutes a digest match. No reopen by path for hashing.
- GetFileInformationByHandleEx(FileIdInfo): record UInt64 volume serial and the
  128-bit file ID. Unsupported query fails observation; no weaker silent fallback.
- GetFinalPathNameByHandleW(FILE_NAME_NORMALIZED | VOLUME_NAME_DOS): one bounded
  32,768-WCHAR buffer. Reject failure, truncation, invalid UTF-16/NUL and unsupported
  non-local-DOS forms. Preserve the actual result, not a substituted expected path.

All size/hash/identity/path observations use the same retained handle. Compare the
actual digest against the embedded expectation before Proof.BeforeCreate or any
CreateCalls increment. A mismatch is a preflight refusal, not a native create
failure. File-only Task 1 harnesses never create a fixture child. The trusted runner must
still invoke those file-only harness executables; that is not forbidden process
creation under this boundary.

For Task 2, the existing Launch obtains its application, working directory and
Binary command from the sealed binding after image preparation and both sharing
denials, before `Proof.BeforeCreate`/`CreateCalls`. After a known successful
CreateProcessW return, retain and validate both exact original handles first, then
query only `Original.Process` using `QueryFullProcessImageNameW(...,0,...)`, once,
with capacity 32,768 WCHARs. Never reopen by PID, query a substitute handle, retry
this image query, or release the original process handle first.

### One path grammar and comparison

Extract `FixedImagePath` into `tests/windows/NativeFixedImagePath.cs`, without owner,
expectation or native dependencies. `Validate(string raw)` returns the unchanged
raw string; `Comparable(string raw)` validates and removes only an exact ordinal
`\\?\` prefix followed by `[A-Za-z]:\`; `Agree(string held,string process)`
compares those results with `StringComparison.OrdinalIgnoreCase`. Counts/bounds
are UTF-16 code units: nonempty, <32,768 units, valid paired surrogates, no NUL or
Unicode category Cc (`0000..001f`, `007f..009f`), and a drive-absolute DOS prefix
`[A-Za-z]:\`. Reject UNC, device/volume-GUID, drive-relative and slash-root forms.
Keep this existing bounded grammar rather than silently applying filesystem
canonicalization. Do not resolve dots, fold separators, trim, expand short names,
normalize Unicode, remove another prefix, or claim different spelling is identity.
Both query paths and held paths call this same function. Preserve their actual raw
forms separately; inability to serialize a malformed/truncated return leaves the
path null with an explicit invalid-path outcome, never a substituted expected path.

Python validates the identical code-unit grammar and Cc range. It may decide
OrdinalIgnoreCase only when lengths differ (necessarily unequal), units are
identical, or every differing unit is ASCII (fold only ASCII A-Z, leaving all
non-ASCII units identical). A changed non-ASCII unit is indeterminate to this
portable fast path, never processed with `casefold`, Python `upper` or a different
Unicode table. Resolve it through fixed `check_native_fixed_image_paths.ps1`,
which loads the fixed shared path source with a constant public managed comparison
wrapper (no native/owner API) and executes the actual internal `Agree` under **Windows PowerShell
5.1 on Windows .NET Framework 4.8**, the native harness runtime. The bridge accepts
only a bounded stdin batch of path pairs, returns ordered comparison results, and
has no caller-supplied source/executable selector. Gate the runtime explicitly;
pwsh/.NET Core, even with net48 references, cannot stand in for it. The Python
validator's `path_comparer` dependency is a fixed bridge adapter, not an artifact-
provided command. If exact comparison is needed but that runtime is unavailable,
the validator must reject every composed PASS summary with an unavailable-
comparison error, even when require_pass=False. It may accept only structurally
consistent FAIL diagnostics, with the affected case FAIL/overall UNKNOWN, without
certifying the unverified relation. require_pass=True still rejects those diagnostics.

Pin prefix/plain, ASCII drive/name case, unchanged Cyrillic/CJK/emoji, genuine
path differences, C0/DEL/C1 controls, unpaired surrogate, NUL, exact bounds, UNC,
Unicode composed/decomposed differences and `Straße` versus `STRASSE`. On Windows
also test a differing non-ASCII case pair through the real net48 bridge. In 2B wire
`.github/workflows/native-tests.yml` to run, under shell=powershell on windows-2022,
`python -X utf8 tests/test_native_fixed_image_observation_contract.py FixedImageWindowsPathBridgeContracts.test_nonascii_bridge_uses_windows_framework -v`
before its existing fixed-image observation step. That test calls the fixed bridge
via `%SystemRoot%/System32/WindowsPowerShell/v1.0/powershell.exe`, requires its
Windows PowerShell 5.1/Framework runtime gate, forces a changed non-ASCII case
pair (not the portable fast path), and records the host identity and actual result.
It must fail, not skip, on that Windows runner if the bridge/runtime is unavailable.
Add the narrow path-source/bridge-script workflow triggers in 2B. Until this exact
assertion is actually observed, its Windows runtime gate remains pending in every
later task/checkpoint; later managed passes cannot discharge or erase it. Linux
compilation/managed tests prove their own runtime behavior only; they do not claim
cross-runtime Unicode equivalence. Native validation and independent acceptance
must identify the host used when the exact bridge is needed.

## Native ownership and return evidence

Each open/read/close has an irreversible entered state set before the call and a
separate recorded native return. A successful open stores the exact handle in its
rooted owner before further work. INVALID_HANDLE_VALUE is a known open failure,
not an owned handle. Unknown open return retains the owner and forbids retry.
Reads advance only after known successful returns; partial reads are permitted,
but unknown return poisons observation and forbids further read/close reuse.

Checked CloseHandle on the exact owned handle is the only explicit native-release
proof. Known FALSE or unavailable close return is unresolved; never close again.
Model these faults without creating real uncertain/leaked native operations. Root
unresolved owners through harness exit and stop new cases. Process teardown is not
explicit resource-release evidence.

Task 1 releases a known file handle after terminal synchronous file observations,
including known preflight rejection. Task 2 retains it through the existing owner
lifetime gates, including capture, terminal I/O and original-handle exit observation.
Unknown creation outcome retains it. Image release participates in owner release
status; diagnostic failure remains sticky UNKNOWN even after successful release.

## Existing-owner ordering and injectable boundaries

The actual `Run` decisions stay in one place: UseOnce; prepare image/probes; if
refused skip transport/create/query; otherwise prepare existing transport; execute
existing Launch; close parent writers after a known create return; pump and inspect
sentinel after known success/valid originals; finally Refresh, bounded Recover as
needed, and gated Release. Image preflight occurs before any transport allocation.
On expected preflight refusal, Refresh sees terminal never-issued slots and release
can resolve the image without ever entering create. Do not invent process EOF or
exit observations for that branch.

Keep `nativeOutcomeUnknown` for uncertain acquisitions/existing operations only.
Known create success with validated originals ends that acquisition uncertainty.
Query FALSE, export/return unavailable, invalid/truncated path or path mismatch
sets sticky diagnostic UNKNOWN via `Proof.Fault()` and the query ledger. It must
not set the acquisition flag or skip writer closure, pumping, exit polling or
otherwise eligible release. Isolate query exceptions in `ObserveProcessImageOnce`,
so they do not leave the Run continuation. Unknown create return or missing original
handles is different: do not query or pump a possibly unowned process, do not close
its resources/image speculatively, retain and stop later cases.

Use these internal seams in the real methods, not a parallel lifecycle model:

| Interface/file | Exact responsibility and tests |
| --- | --- |
| `IFixedImageNativeCalls` in `NativeFixedImageIdentity.cs` | `FixedImageCallDomain Domain { get; }` and methods matching existing CreateFileW, Attributes, GetFileSizeEx, Identity, GetFinalPathNameByHandleW, ReadFile, CloseHandle plus `CaptureLastError()`. Both image and probes use its one immutable adapter; no residual static native call on their fake path. Known-false error captured immediately. |
| `IChildCaptureProcessCalls` in `NativeFixedImageComposition.cs` | `FixedImageCallDomain Domain { get; }`; `CreateProcessW` with the existing argument/ref/out signature; `QueryFullProcessImageNameW(IntPtr,uint,StringBuilder,ref uint)`; `WaitForSingleObject(IntPtr,uint)`; `GetExitCodeProcess(IntPtr,out uint)`; `CloseHandle(IntPtr)`; `CaptureLastError()`. Existing Launch, ObserveExit, InspectSentinel wait and exact original process/thread close call this adapter. Query uses original process, never thread/PID. |
| `IChildCaptureFlow` in `NativeFixedImageComposition.cs` | `FixedImageCallDomain Domain { get; }`; `PrepareTransport(ChildCaptureOwner)`, `CloseParentWriters(ChildCaptureOwner)`, `Pump(ChildCaptureOwner)`, `InspectSentinel(ChildCaptureOwner)`, `Recover(ChildCaptureOwner)`. Native adapter forwards to those existing methods; Run owns every branch and release decision. Recording flow supplies only scripted transport events, not decisions about create/query/release. |
| `ChildCaptureOwner` real integration methods | `PrepareImageOnce()`, `ObserveProcessImageOnce()`, `ObserveExit()`, `Release()` and `Run()` execute identical guards/ledgers with native or recording adapters. Refactor visibility only as needed for the internal flow, not public APIs. |
| `FixedImageCompositionTestRig` in `NativeFixedImageCompositionTests.cs` | A closed managed factory creates a fake image adapter, fake process calls, recording flow and fake fresh-sentinel calls together, bound by one private domain token. Its owner/image factory cannot mix a synthetic image with a native process/flow adapter. No runtime harness flag chooses this rig. |

`FixedImageCallDomain` is an internal sealed identity token with one native
singleton and distinct recording tokens. Native adapters expose only the singleton.
`FixedImageCompositionBindings` is an immutable internal bundle of process calls,
flow and fresh-sentinel calls. `Native` installs only native adapters; its recording
factory validates identical nonnative tokens for image/process/flow and rejects
`SentinelNativeCalls` for the fresh-sentinel member. A recording token cannot be
installed by a native factory; tokens/adapters cannot be replaced after creation.
This is a test wiring guard, not authentication against malicious same-assembly code.

For injected file-owner tests, internal
`FixedFixtureImage.CreateForRecording(IFixedImageNativeCalls calls,
FixedImageCallDomain domain)` validates a matching recording adapter/domain and
still uses genuine embedded build expectations and the fixed sibling binding;
it accepts no path/digest/length overrides. The rig constructor consumes a managed
`byte[] pristineBytes`, verifies its length/SHA-256 against those constants and
clones it. Managed runners read this input from the shared build's completed
PristineChild before mutation. Fake successful ReadFile calls return those actual
bytes; a synthetic digest or placeholder child cannot satisfy preparation.
`NativeFixedImageIdentityTests.RunInjectedOwners(byte[] pristineBytes)` and
`NativeFixedImageCompositionTests.RunManaged(byte[] pristineBytes)` are managed
harness entry methods only, never parameters to a native executable. In 2C,
`check_native_fixed_image_observation.ps1` must call the real integer-returning
RunInjectedOwners after Assert-FixedFixtureBuild and a managed read of verified
PristineChild bytes, before negative setup, on managed-only and native runner paths.
A nonzero return fails the runner. The method emits `PASS fixed image injected owners`
only after its real-method fake-call assertions pass; a managed runner test requires
that marker exactly once, proving invocation rather than mere compilation.

`FixedImageCompositionTestRig.CreateOwner()` calls the actual injected constructor/
claim path with its immutable bindings. Its fake PrepareTransport uses actual `PrepareFreshSentinel` with fake calls
and leaves real pipe/allocation handles zero. Recording writer-close, sentinel
inspection and recovery forward to the real owner methods: zero transport handles
need no P/Invoke, sentinel wait uses the fake wait adapter, and empty slots poll
without a native call. Its fake Pump feeds bounded bytes and
EOF through the actual PipeCapture event methods, invokes the real ObserveExit
through fake process calls and returns to the real Refresh/Release. Exact original
process/thread closes go through the same fake process adapter, sentinel close
through the existing fake sentinel adapter, and image/probe closes through the fake
image adapter. Never put synthetic handles into real pipe slots, unmanaged buffers
or static P/Invoke. Default never-allocated slots are terminal/released naturally;
this is orchestration coverage, not evidence that native overlapped I/O happened.
Unknown-create tests throw at the fake Create boundary, leaving the real entry
ledger unknown. Image-close false/unavailable tests execute the real close ledger
through the fake file adapter. No reflection-only fabricated state is sufficient.
Tests assert a complete call trace, including no native adapter entries. Retain all
existing native/managed sentinel tests and nine native capture cases unchanged.

Before wiring a new fake call, inventory every downstream close/wait/slot action:
if the fake can reach a real P/Invoke, stop that subtask and repair the seam first.
The flow seam is not permission to relocate or duplicate Launch/Pump/Release logic.

`ObserveExit` records each actual most-recent wait entry/return and exit-code query
entry/return/error. Record the actual wait UInt32, including 258 and 0xffffffff;
never derive WAIT_OBJECT_0 from `ExitObserved`. Only a returned wait 0 followed by
a known successful GetExitCodeProcess can set ExitObserved/code. Existing bounded
polling/recovery is preserved (connect <=1 s; Pump <2 s and <32,768 rounds;
Recover <300 ms); no query retry or new
unbounded wait is added. A subsequent unavailable wait/code call has null return
fields for that attempt, not a zero or a stale earlier result.

After known precreate refusal or known FALSE create, normal resolved transport and
allocation gates permit checked image close. After known successful create the
image remains held through both EOFs, exact terminal I/O and original-handle exit
observation. The composed Release branch additionally requires both EOF facts before
closing the image or marking the whole owner released; the legacy Proof.CanRelease
condition alone does not imply EOF. Preserve legacy release behavior outside the
new composed mode. Release closes originals/transport by the existing gates, then the
image exactly once. Overall Released/Proof.HandlesClosed include the image and both
probes. Any uncertainty, known FALSE close, unresolved I/O or unobserved exit keeps
the appropriate owners rooted and stops later cases. Query-only diagnostic UNKNOWN
remains sticky even when every resource is successfully released.

## Harmless coverage and evidence

All negative setup occurs before opening the image, in fresh owned build copies:

- Matching image: actual length/hash/identity/path, then explicit file release.
- Same-length digest mismatch: change one deterministic byte in an owned copy of
  the harmless child, preserving length and the original embedded expectation.
  Never execute that copy. Assert digest comparison was reached and rejected.
- Size mismatch: append one harmless byte before opening. Assert size rejection,
  distinct from digest rejection. Never execute that copy.
- Missing image: omit or move only the owned fixed sibling before the attempt.
- While held, separate GENERIC_WRITE and DELETE-access probes use OPEN_EXISTING
  and FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE. Their own sharing
  must permit the existing reader, so failure cannot be caused by an incompatible
  probe share mask. Capture GetLastWin32Error immediately after each failed open;
  require ERROR_SHARING_VIOLATION. Do not write, delete, truncate or request
  delete-on-close. Checked CloseHandle must close an unexpectedly successful probe;
  fail that case even if close succeeds, retain uncertainty if it does not. Pin
  these exact access/share/disposition arguments with a managed call-contract test.

Every negative case must prove zero CreateProcessW entries in Task 2; Task 1 has no
launcher for a fixture child. Build four separate harnesses, each with exactly one
compile-time case constant from the fixed four-case allowlist below. All four embed
the same pristine child expectation unchanged. Only afterward prepare the negative
child copies in their separate fixture directories. Each harness accepts no
arguments and opens only its own fixed sibling. The trusted runner invokes these
fixed harnesses and aggregates records in the specified order; no runtime
path/digest/case selector is introduced. Never regenerate expectations after
negative setup. Isolate cases so corrupted/missing images cannot carry into a
positive launch. No exploit, race or hostile replacement reproduction.

## Separate artifact contract (version 1)

The accepted Task 1 schema remains version 1 and accepts only `stage=file-only`.
The proposed Task 2 schema below is separate version 2, pinned to `stage=composed`;
it is unavailable until composition preflight review and the controller's
implementation assignment.

`native-fixed-image-observation.jsonl` is UTF-8 text, at most five records, 16 KiB
per line including newline and 128 KiB total. Each record has exact keys; reject
duplicate/unknown keys, wrong types, invalid UTF-16/NUL in strings, excess bounds
and trailing records. Do not truncate observations into apparently valid evidence.

Case order is exactly `matching-image`, `digest-mismatch`, `size-mismatch`,
`missing-image`. Each case record has only these keys:

- `kind`: `fixed_image_case`; `schema`: integer 1; `stage`: `file-only`;
  `case`: one name above; `status`: `PASS` or `FAIL`; `mutation_authorized`: false.
- `refusal`: `none`, `digest-mismatch`, `size-mismatch`, `missing-image` or
  `observation-failure`; `create_calls`: nonnegative integer.
- `expected_size`: positive integer <=16 MiB; `expected_sha256`: 64 lowercase hex.
  These are generated expectations, never actual observations.
- `open_state`: `not-entered`, `return-unknown`, `returned-failure` or
  `returned-success`; `open_error`: UInt32 only on returned-failure, otherwise null.
- `actual_size`: nonnegative integer or null; `actual_sha256`: 64 lowercase hex or
  null; `bytes_hashed`: nonnegative integer; `read_state`: `not-entered`,
  `return-unknown`, `returned-failure`, `known-incomplete` or `complete`; `read_error`: UInt32 only on
  returned-failure, otherwise null; `eof_request_bytes` and `eof_return_bytes`:
  integers for the known successful terminal read, otherwise both null.
- `volume_serial`: 16 lowercase hex or null; `file_id`: 32 lowercase hex or null;
  `held_path`: nonempty actual local DOS path or null.
- `write_probe` and `delete_probe`: null when not attempted, otherwise objects with
  exactly `access` (respectively `GENERIC_WRITE` or `DELETE`), `share` (integer 7),
  `disposition` (integer 3 for OPEN_EXISTING), `open_state`, `open_error`, and
  `close_state`. Open states/errors follow the rules above.
- `close_state`: `not-opened`, `not-entered`, `return-unknown`, `returned-failure`
  or `returned-success`; applies to the exact owned image/probe handle.
- `process_observation`: always null in file-only schema 1. The unimplemented
  composed observation is specified separately below, not accepted through this key.

Unavailable means JSON null, never empty string, zero, expected-value substitution
or a made-up observation. Zero is valid only where it is an actual count/result.
The bytes_hashed counter starts at zero; other not-entered observations remain null.
No standalone `hash_matches`, `sharing_denied` or `released` Boolean substitutes
for evidence. A structurally valid report is not proof the native calls occurred;
acceptance additionally requires independently reviewed exact-source native runs.

Every PASS case except missing-image requires open_state=returned-success and
open_error=null. actual_sha256 is present only after a complete successful read;
failed/incomplete reads never publish a partial hash as an image digest.
Use read_state=known-incomplete when successful native reads are followed by
premature EOF, extra terminal bytes or managed hashing failure: read_error=null
and actual_sha256=null. Preserve any actual successful terminal read counts rather
than inventing a native error. Reserve complete for a full digest and the required
positive-size EOF proof. known-incomplete can appear in valid FAIL diagnostics,
never a PASS case.
A PASS matching case requires matching sizes/digests, bytes_hashed=expected_size,
read_state=complete, eof_request_bytes=1, eof_return_bytes=0, actual identity/path,
image close returned-success, and both probes with returned-failure/error 32 and
close_state=not-opened. A PASS digest mismatch requires equal sizes, a complete hash
with the same EOF proof but unequal digests, and checked image release. Size mismatch
requires unequal actual/expected sizes, no hash/read entry and checked image release.
Missing image requires returned-failure/error 2, no file observations or probes,
read_state=not-entered, bytes_hashed=0 and close_state=not-opened. Probes are confined
to matching-image. All file-only cases require create_calls=0 and process_observation=null.
Inconsistent or missing required observations fail.

The final record has exactly `kind`=`fixed_image_summary`, `schema`=1, `stage`,
`status`, `cases` (case-record count), `failed` (FAIL-case count), `stop_reason`
(`none`, `case-failure`, `unresolved-owner`, `build-failure` or `evidence-failure`),
and `mutation_authorized`=false. Stage must agree across records. PASS requires all
four ordered PASS cases, cases=4, failed=0 and stop_reason=none. Structurally valid
failure diagnostics may contain an ordered prefix, including zero cases for build
failure, followed by FAIL summary with consistent counts and non-none stop_reason.
Include the attempted case whenever possible; unresolved-owner stops later cases.
Never fabricate absent later cases. Validators distinguish valid diagnostics from
acceptance: require-pass rejects every FAIL summary and every incomplete sequence.
Reports never provide release, retry or cleanup authority.

Task 1 includes narrowly scoped CI path triggers, file-only execution and this
separate bounded artifact. Independently reviewed exact-source Windows file-only
results are a prerequisite to beginning Task 2, not merely its final acceptance.

## Proposed composed evidence (schema 2, stage=composed)

Keep the same separate filename, four-case order, <=5 records, <=16 KiB UTF-8 per
line and <=128 KiB total. Retain all schema-1 file/probe field names and meanings,
but schema=2/stage=composed, create_calls is exactly 0 or 1, refusal additionally
allows `sharing-failure`, and add exactly one top-level `composition` object.
`process_observation` has the new exact shape below. No optional extra keys, raw
handles, PIDs, convenience success booleans or mutation authority are introduced.
File-only version 1 remains accepted only by the file-only runner/validator mode.

`composition` has exactly:

- `claim_state`: `claimed` (no valid composed report without actual transfer).
- `create_state`: `NotEntered`, `EnteredReturnUnknown`, `ReturnedFalse`, `ReturnedTrue`.
- `create_error`: UInt32 only for ReturnedFalse, otherwise null.
- `original_handles_state`: `not-observed`, `valid` or `invalid`; not-observed unless
  ReturnedTrue, then valid only if both original handles passed the existing checks.
- `overall`: `OBSERVED` or `UNKNOWN` (sticky diagnostic outcome).
- `image_release_state`, `owner_release_state`: each `released` or `retained`.
  Image state includes probes. Owner released requires image released plus every
  existing parent resource/allocation gate. Image released alone cannot hide a
  retained transport/process owner.
- `capture`: null unless ReturnedTrue with valid originals; otherwise the exact
  capture object described next, including partial/failure observations.

`capture` keys are exactly `stdout_bytes`, `stderr_bytes`, `stdout_hash`,
`stderr_hash`, `eof_stdout`, `eof_stderr`, `io_terminal`, `sentinel_probe`,
`sentinel_unsignaled`, `one_shot_refused`, `rounds`, `fault_site`,
`evidence_bytes_written`, `held_writer_blocked_eof`, `wait_calls`, `exit_code_reads`,
`channels`. Use existing counter/hash/Boolean bounds. `channels` is exactly two
objects in stdout/stderr order, with the eight existing ChannelReport keys
(`retained`, `discarded`, `read_issued`, `read_terminal`, `read_pending`,
`read_immediate`, `read_visits`, `max_read_gap`) plus `read_released` and
`connect_released`. Actual initial zero counters remain counts, not evidence of
native activity. No default exit code is copied from the legacy serializer.

`process_observation` is null unless ReturnedTrue with valid originals. Otherwise
it has exactly:

- `query_state`: `not-entered`, `return-unknown`, `returned-failure`, `returned-success`;
  `query_error`: UInt32 only for returned-failure; `query_return_chars`: UInt32 only
  for returned-success, otherwise null. The mutable input capacity is not a return.
- `image_path`: actual raw well-formed/NUL-free bounded query string or null.
  `path_state`: `not-observed`, `unavailable`, `malformed`, `truncated`,
  `unsupported`, `valid`. Only a valid complete returned count/string has valid
  state. Unsupported but well-formed bounded raw strings may be retained as FAIL
  diagnostics; malformed/truncated strings are null, never repaired/truncated.
- `comparison`: `not-performed`, `match`, `mismatch`; only both valid paths allow
  comparison. The validator independently checks the relation with the specified
  portable proof or exact Windows bridge, never trusts this label alone. An unavailable
  exact comparison permits only structural FAIL diagnostics, never a PASS summary
  in either require-pass mode.
- `exit_wait_state`: `not-entered`, `return-unknown`, `returned`;
  `exit_wait_result`: actual UInt32 iff returned, otherwise null;
  `exit_wait_error`: actual UInt32 only for returned WAIT_FAILED (0xffffffff).
- `exit_code_state`: `not-entered`, `return-unknown`, `returned-failure`,
  `returned-success`; `exit_code_error`: UInt32 only for returned-failure;
  `exit_code`: actual UInt32 only for returned-success following returned wait 0,
  otherwise null. A 259 result is still an actual code after a signaled wait.

All nullable fields are null outside their stated return states; all errors are
captured immediately at the matching known-false boundary. `not-entered` query
has path_state=not-observed and no comparison. Unknown/FALSE query has unavailable
path and no comparison. A successful query with count 0 or invalid UTF-16 is
malformed; count >=32768 or inconsistent buffer/count is truncated. A valid query
must have 0<count<32768 equal to its raw UTF-16 unit count. Invalid query outcomes
cannot be marked OBSERVED/PASS. Retained original handles are never serialized.

### Required case and failure matrix

| Condition | Create/query/capture | Image and owner disposition; evidence/status |
| --- | --- | --- |
| Matching pristine image and both sharing denials | 1, ReturnedTrue, valid originals, one matching query; full Binary capture | Both released; file digest/identity/path complete; wait returned 0, code returned 0; overall OBSERVED; PASS only with every Binary assertion below. |
| Missing image | 0, NotEntered; query/process/capture null | Known open FALSE/error 2, no file ownership; both resolved/released; expected refusal missing-image; PASS negative. |
| Size mismatch | 0, NotEntered; no query/capture/read entry | Unequal actual size, no hash; checked image close; both released; PASS negative. |
| Same-size digest mismatch | 0, NotEntered; no query/capture | Full actual digest/EOF, unequal digest and equal size; checked image close; PASS negative. |
| Probe unexpected success or wrong known error | 0, NotEntered; no query/capture | sharing-failure/UNKNOWN/FAIL; close only actually acquired probe once; image close allowed only after probes resolve. |
| File/probe open/read/close return unavailable or close FALSE | 0 if precreate; no query/capture | Retain unresolved exact owner; FAIL/unresolved-owner; stop later cases, no retry. |
| Known FALSE create | 1, ReturnedFalse, actual create error; no original query/capture | UNKNOWN/FAIL; known-not-created may release image only after existing transport/allocation gates resolve. |
| Unavailable create return | 1, EnteredReturnUnknown; no error/query/capture | UNKNOWN/FAIL; retain image and composed owner, no speculative cleanup; unresolved-owner. |
| TRUE create with invalid original handles | 1, ReturnedTrue/invalid; no query/capture | UNKNOWN/FAIL; retain image/owner; unresolved acquisition, no PID repair. |
| Query FALSE/unavailable/malformed/truncated/unsupported/mismatch | 1, ReturnedTrue/valid; query ledger names exact outcome; capture continues | UNKNOWN/FAIL; normal drainage, wait/code observation and release still required/allowed. Released owners yield case-failure; unrelated unresolved gates yield unresolved-owner. |
| Exit wait/code unavailable or no exit before bounded deadline | 1, ReturnedTrue/valid; retain actual/null wait/code result, partial capture | UNKNOWN/FAIL; image and originals retained until existing gates prove exit; unresolved-owner, never synthetic wait 0. |
| Image close FALSE/unavailable after completed capture | 1, successful query/exit/capture may remain visible | UNKNOWN/FAIL; image and whole owner retained even if other handles closed; no retry, unresolved-owner. |

The three expected negatives are passing tests with **zero** Proof.BeforeCreate and
CreateProcess entries, no image query, no transport setup, and resolved ownership.
They are not synthetic native-create failures. All unexpected preflight failures
are FAIL. For query failures release is permitted, not guaranteed without the
unchanged lifecycle gates. Never represent unknown acquisition as diagnostic-only.

Positive native coverage must call the existing `NativeChildCaptureNativeTests.AssertCase`
with only its visibility widened to internal. Do not replace or weaken it. For
Binary it requires complete/released/known owner, actual exit 0, one create, positive
wait/code counts, PVC2 EXCLUDED and independent sentinel unsignaled, fault_site=0,
evidence_bytes_written=0, no held-writer fault, stdout 4105 bytes/hash
`031381f5c4fbe740`, stderr 257 bytes/hash `c98455caf71ceb86`, both EOFs, bounded
retained bytes, terminal/released connect/read slots, fair visits equal to rounds
with max gap <=1, and second Run refusal with unchanged rounds/release. The composed
validator checks the corresponding capture fields as well as image/query evidence.
Baseline nine-case and three-environment native assertions/schemas remain intact.

Schema-2 summary has the same exact summary keys as schema 1, with schema=2 and
stage=composed. PASS still requires exactly four ordered passing cases and no stop
reason. `unresolved_owner` includes file/probes **or** composition.owner_release_state
retained, unknown create/invalid originals, unobserved exit after known success,
and unresolved transport state. The last attempted case must be FAIL when retained;
it must terminate the prefix with stop_reason=unresolved-owner. A resolved failed
case may precede later cases; summary is FAIL/case-failure unless a later owner is
unresolved. Never fabricate missing cases or change a FAIL into expected-negative
PASS. Build/evidence failures may produce the existing bounded zero/partial prefix.

Python interfaces become `validate_records(records, require_pass=False,
expected_stage='file-only', path_comparer=None)` and the corresponding
`validate_evidence`. The composed runner must pass `--expected-stage composed`
for diagnostic validation and require-pass, and reject schema-1/file-only records
even if all four passed. The legacy runner explicitly pins file-only. No artifact
chooses its own acceptance mode. Serialize immutable snapshots only after Run and
one-shot assertion; neither validator nor any report confers cleanup authority.

## Explicitly unproved

The build itself, harness, ancestor identity/ACLs, configuration, dependencies, CLR
behavior and loaded bytes are not attested. CreateProcessW opens by path rather
than by the retained image handle. Sharing denial concerns ordinary new leaf opens,
not existing writable mappings or all possible modification mechanisms. Post-launch
path observations cannot retroactively admit execution. Production suspended-before-
runnable lifetime design is a separate prerequisite, not silently added here.
Windows interactive acceptance and all existing release gates remain unchanged.
