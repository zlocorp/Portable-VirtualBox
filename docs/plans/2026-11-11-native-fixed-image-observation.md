# Native Fixed-Image Observation Implementation Plan

> Execute each stage with TDD and independent review; steps use checkboxes.
> Keep contributions on the Draft branch and review each stage before its successor.
> Task 1 and Tasks 2A–2B are test-only accepted; Task 2C source/limited proof is accepted.
> Current 2D/2E source/managed work and independent whole-composition source review
> are complete, with no open source findings. Fresh exact-source Windows/native
> execution and independent actual-artifact acceptance remain pending.
> The historical fc6abad prerequisites and failed/blocked 6a164db checkpoint,
> including its pause, remain source-specific records.
> Draft publication and hosted native execution require separate authorization.
> No production integration, merge, release or primary-host execution follows.

**Goal:** Observe a fixed harmless build image and refuse unexpected bytes before
native creation, without treating matching bytes as privileged admission.
**Architecture:** A sealed exact-native-file owner consumes build-generated
expectations. First verify it without a process; then opt into the existing
ChildCaptureOwner without duplicating launch/capture logic.
**Tech Stack:** C# 5 x64 .NET Framework 4.8, Windows PowerShell 5.1, Python unittest.
**Spec:** [Fixed-image observation](../designs/native-fixed-image-observation.md).

## Global constraints

- Preserve all nine baseline and three environment cases and both artifact schemas.
- No external native-entry path/digest/manifest inputs and no arbitrary launcher.
- Keep generated expected bytes separate from runtime observations; missing/stale
  build input fails closed. Never regenerate after preparing a negative copy.
- Open/read/close unknown-return states are one-shot and retained; model these
  without creating real uncertain native operations.
- Same-length corruption must reach the hash comparison; appending tests only size.
- Process-image query uses only Original.Process; post-create failures still drain.
- Existing managed FileStream disposal does not become verified native close.

## Review focus

- A generated owner dependency can break direct Add-Type consumers before any test:
  Task 2A covers every entry and builds the independent child first.
- A facade retained by its caller can close a transferred image or reuse released
  readiness: Task 2C pins exclusive irreversible claim and live Ready semantics.
- A failed image query can incorrectly poison acquisition and skip drainage:
  Task 2D distinguishes diagnostic UNKNOWN from unknown create/operation ownership.
- A fake process handle can escape into a real wait/close/pipe call: Task 2D uses
  a closed recording domain and traces the actual Run/Release branches.
- Unicode tables and legacy file-only success can falsely validate composed PASS:
  Tasks 2B/2E pin path proof/runtime and stage-specific schemas and failure prefixes.

## Task 1: File-only exact owner and build expectation

**Create:**
- `tests/windows/NativeFixedImageIdentity.cs`: closed owner, interop and pure state.
- `tests/windows/NativeFixedImageIdentityTests.cs`: managed contracts.
- `tests/windows/NativeFixedImageIdentityNativeTests.cs`: file-only native cases.
- `tests/windows/check_native_fixed_image_observation.ps1`: closed fixture build,
  expectation generation, isolated benign cases and bounded evidence.
- `tests/test_native_fixed_image_observation_contract.py`: behavioral build/tests
  and strict separate artifact validator.

**Modify:** `.github/workflows/native-tests.yml` for narrowly scoped new file
triggers, a file-only step and its separate bounded text artifact.

**Generated, retained outside source tree:** `FixedFixtureBuildExpectation.g.cs`.

**Interfaces:** `FixedFixtureImage.CreateForObservation()` returns unopened sealed
owner; `PrepareOnce()` opens/observes fixed sibling; `TryRelease()` returns checked
release status. Immutable observations distinguish size/hash/open refusal from
unavailable evidence. Native ownership stays private. Task 2 must root and own this
context, not pass raw paths or handles into a new launcher.

- [x] Write behavioral tests for exact expected digest/length parsing, 2 KiB source
  bound, immutable observations, single-use preparation and all open/read/close
  entry/return transitions. Unknown return forbids reuse; known failed close never
  retries. Exercise 16 MiB and 64 KiB boundaries, partial reads, premature EOF,
  impossible counts, read errors, unsupported identity and malformed/truncated paths.
  Require a positive one-byte terminal read returning TRUE/zero even at exactly
  16 MiB; reject zero-length reads as EOF proof and reject a returned extra byte.
- [x] Run the new Python test module and witness failing behavioral assertions.
- [x] Implement the spec's bounded native owner and checked CloseHandle state. Keep
  native faults modeled; do not inject real uncertain calls.
- [x] Build the harmless child, generate bounded fixed-syntax expected constants,
  then compile four separate file-only harnesses, each with one compile-time case
  constant from the fixed four-case allowlist and the same unchanged pristine
  expectation. Prepare negative copies only afterward. Each harness accepts no
  arguments and opens its own fixed sibling. The runner invokes these fixed
  harnesses and aggregates their records in order. Retain generated source and files; fail on
  stale/missing inputs. Pin managed-only compile behavior without executing child.
- [x] Add isolated native cases for matching bytes, same-length digest mismatch,
  distinct size mismatch and missing sibling; add no-write/no-delete sharing probes
  to the positive case. Same-length mismatch must report hash comparison reached.
  Pin each probe to share mask 7, OPEN_EXISTING, exact write or DELETE access,
  immediate error capture and checked close on unexpected success. Add a managed
  call-contract test rejecting incompatible probe sharing as false assurance.
  No fixture child is created by a Task 1 harness. The trusted runner may invoke
  the file-only harness executables; that is necessary and within this boundary.
- [x] Implement and mutation-test the separate artifact validator, including exact
  version-1 fields, four ordered cases, null unavailable values, native-result
  consistency and mutation_authorized=false. Reject forged success booleans, empty
  observations and zero-length EOF claims. Accept a bounded ordered prefix plus
  consistent FAIL summary as diagnostics when unresolved ownership stops cases;
  require-pass must reject that prefix. Test duplicates, reordering, summary count
  mismatches, extra records and truncation independently. Add serializer/validator
  tests for known-incomplete after premature EOF, extra terminal bytes or managed
  hashing failure: read_error=null and actual_sha256=null. Accept it only as FAIL
  diagnostics; reject PASS. Reserve complete for full digest plus positive-size
  EOF proof, keeping observed terminal counts without inventing native failures.
- [x] Add narrowly scoped CI triggers, file-only execution and the separate bounded
  artifact in Task 1. Preserve existing steps and timeout; invoke only the fixed
  file-only harnesses, none of which launches a fixture child.
- [x] Run `python -X utf8 -m unittest discover -s tests -p test_native_fixed_image_observation_contract.py -v`.
  Run C# 5/x64 warnings-as-errors compilation and PowerShell parse checks. On a
  permitted Windows test runner execute `./tests/windows/check_native_fixed_image_observation.ps1`.
  Record unavailable native execution as pending, never a local managed pass.
- [x] Obtain independent review of provenance, same-handle observations, ownership
  and actual exact-source Windows file-only artifacts before beginning Task 2.
  Local managed passes or pending native runs cannot satisfy this prerequisite.
  This stage is independently useful without launching a process or modifying
  ChildCaptureOwner; publish only through a separately authorized branch process.

## Task 2: Source/managed composition complete; native acceptance pending

**Historical gate before 2A:** Task 1's accepted historical record is retained below. The
successor `519056432b4d9bd045140d2ba2bbe924e5c135e9` sentinel native artifacts have
now been independently accepted, including unchanged file-only image results.
That satisfies the changed-source native prerequisite. Obtain independent review
of the revised design/plan before the next implementation stage. Every subtask
below is sequential and ends in focused independent review; do not start its
dependent subtask first. Contributions remain on the Draft branch. Publication,
native execution and exact-source final acceptance retain separate review gates.
No primary/user Windows experiments are included.

**Accepted scope at 98bec8f:** Independent preflight, 2A, 2B and the bounded
host-frame correction reviews are complete. The actual changed-source native
build/path prerequisite is accepted in the
[execution record](../EXECUTION-2026-11-11-fixed-fixture-build-paths.md).
At that historical checkpoint only 2A–2B were accepted. The later 2C source/limited
proof and historical 6a164db blocked/pause decision are recorded below. The
historical fc6abad checkpoint permitted test-only 2D to resume. The current
source-only checkpoint below records completed 2D/2E source work, including actual
composed-validator/status-guard integration, not fresh Windows/native acceptance.

### Shared files and interface preflight

| Owner subtask | Files/interfaces it establishes | Downstream consumers and review stop |
| --- | --- | --- |
| 2A build graph | New `tests/windows/NativeFixedFixtureBuild.ps1`: New-FixedFixtureBuild, Assert-FixedFixtureBuild, Get-FixedFixtureConsumerSources; unchanged generated-source format | All three existing runners and four direct Python owner compiles, then new composition consumer. Stop if a child source depends on owner/expectations. |
| 2B path semantics | New `tests/windows/NativeFixedImagePath.cs`: Validate, Comparable, Agree; new `check_native_fixed_image_paths.ps1` fixed net48 bridge | Image codec, composed query, Python local_path and comparison validation. Stop rather than assume Linux/.NET Core Unicode equivalence. |
| 2C file ownership | `NativeFixedImageIdentity.cs`: IFixedImageNativeCalls, irreversible ClaimForComposition, nested ownership-only CompositionLease, live Ready; command binding deferred to 2D | Existing file-only harness remains schema 1; owner consumes only private lease. Stop if raw handle/public arbitrary path or external facade mutators escape. |
| 2D composition | New `NativeFixedImageComposition.cs`: IChildCaptureProcessCalls, IChildCaptureFlow, query/wait ledgers; one shared NativeFixedFixtureCommand.cs formatter and lease command binding; `NativeChildCaptureNative.cs` real integration; new `NativeFixedImageCompositionTests.cs` recording rig | Actual Run/Launch/Refresh/Release plus fake boundary tests. Stop if synthetic handles can reach a real native API, or Launch/Pump/Release is duplicated. |
| 2E harness/evidence | New `NativeFixedImageCompositionNativeTests.cs`, `check_native_fixed_image_composition.ps1`; stage-aware serializer/validator; unchanged full Binary assertion shared | New composed artifact, old nine/three/four evidence sets and narrow workflow wiring. Stop if file-only can satisfy composed acceptance or retained owner permits later cases. |

`NativeChildCaptureNative.cs` becomes a partial sealed class only to place the
composition-specific adapters/ledgers in its new companion; retain existing launch,
transport and release implementations. Every source-list consumer of that partial
class receives its companion, image/path sources and generated expectations in
2D as one change. The four direct owner compilation sites are named in the design's
build-consumer table; line references there are 5190564 anchors, not future offsets.

### Task 2A: Make every consumer child-first

**Files:**
- Create `tests/windows/NativeFixedFixtureBuild.ps1`.
- Modify `tests/windows/check_native_child_capture.ps1`,
  `tests/windows/check_native_launch_environment.ps1`,
  `tests/windows/check_native_fixed_image_observation.ps1`.
- Modify `tests/test_native_child_capture_contract.py`,
  `tests/test_native_launch_environment_contract.py`,
  `tests/test_native_fixed_image_observation_contract.py` for build-order/source-list
  contracts and the four direct Add-Type sites.
- Modify `.github/workflows/native-tests.yml` for the narrow helper dependency
  trigger in this task, not deferred to 2E.

**Consumes:** Existing four runtime child sources, C# 5/x64/net48 compiler settings,
fixed expectation format and pinned official reference provisioning.
**Produces:** `New-FixedFixtureBuild([string]$Parent)` with Root/PristineChild/
ExpectationSource/ExpectationSha256; `Assert-FixedFixtureBuild($Build)`;
`Get-FixedFixtureConsumerSources($Build,[string[]]$Names)`. No owner dependency
enters the child. The helper is build-only and never executes generated code.

- [x] Write failing `test_all_owner_consumers_build_child_before_compile`,
  `test_all_three_child_builds_use_only_runtime_sentinel_dependencies`, and
  `test_pristine_expectation_precedes_all_negative_setup`. Assert the two legacy
  runners' first managed compilation occurs after the helper; all four direct
  owner scripts use it; exact four child sources contain no test/owner/generated
  dependency; generated source exactly hashes completed pristine bytes and stays
  unchanged after all harness builds/mutation. Add missing/stale-source failure.
  Add `test_legacy_harnesses_have_verified_pristine_siblings`: each legacy native
  harness has NativeCaptureFixtureChild.exe/config beside it; the child's bytes are
  copied unchanged from verified PristineChild and match its embedded length/hash.
  Add `test_helper_dependency_triggers_native_workflow` for the exact helper path.
- [x] Run the three Python modules below; confirm new assertions fail for the
  specific old ordering, not a missing compiler/reference prerequisite.
- [x] Implement the helper and replace repeated build/generation recipes. Native
  runners build in their fresh root before managed Add-Type. Managed-only routes
  build/hash/compile but never execute child or prepare negative copies. Retain
  configs, generated source and existing full source lists; no stale fallback.
  Copy verified pristine child/config beside each legacy native harness, check the
  copied bytes, and add `tests/windows/NativeFixedFixtureBuild.ps1` to native-tests.yml
  push path triggers in the same 2A change. No new native execution is implied by
  managed-only builds.
- [x] Re-run the three modules and all three `-ManagedOnly` runners with official
  net48 refs. Independently review the source-consumer inventory against the
  design table, including unaffected pure-sentinel and child-output compile paths.
  Record target compilation separately from the actual managed host runtime.

### Task 2B: Pin exact path validation and comparison

**Files:** Create `tests/windows/NativeFixedImagePath.cs`,
`tests/windows/check_native_fixed_image_paths.ps1`; modify
`tests/windows/NativeFixedImageIdentity.cs`, `NativeFixedImageIdentityTests.cs`,
`test_native_fixed_image_observation_contract.py`, helper consumer lists and
`.github/workflows/native-tests.yml` for the exact Windows bridge assertion step
and narrow `NativeFixedImagePath.cs`/`check_native_fixed_image_paths.ps1` triggers.
All unqualified C#/PowerShell paths here and below are under `tests/windows/`;
Python paths are under `tests/`.

**Consumes:** Task 2A source resolution; existing fixed-image bounds.
**Produces:** `FixedImagePath.Validate(string raw) -> string` (unchanged raw),
`Comparable(string raw) -> string` (only exact recognized DOS prefix removed),
`Agree(string held,string process) -> bool` (OrdinalIgnoreCase). The bridge reads
<=4 path pairs/128 KiB UTF-8 total from stdin, validates exact pair keys/types and
path bounds, emits exactly ordered true/false values, rejects arguments and wrong
runtime. It compiles only the fixed repository path source plus a constant public managed
comparison wrapper, then calls the actual shared function under Windows PowerShell
5.1/.NET Framework 4.8; no executable/source selectors. Python comparison returns
known Boolean for the design's portable safe subset, otherwise uses this bridge or
raises unavailable comparison. It never guesses a Unicode relation. Without exact
comparison it may validate only structural FAIL diagnostics (affected case FAIL/
overall UNKNOWN); every PASS summary is rejected even with require_pass=False.

- [x] Write failing `test_path_grammar_cc_utf16_and_prefix_parity` with the design's
  accepted/rejected corpus, including C1 controls currently missed by Python.
  Write `test_ordinal_path_comparison_never_uses_casefold` for prefix/case agreement,
  genuine differences, Straße/STRASSE and composed/decomposed strings.
- [x] Write `test_nonascii_case_requires_exact_framework_bridge`: unavailable or
  .NET Core bridge cannot certify a changed non-ASCII pair; unchanged Cyrillic/
  CJK/emoji and ASCII-only case changes are independently provable without it.
  Add `FixedImageWindowsPathBridgeContracts.test_nonascii_bridge_uses_windows_framework`
  without the existing generic compiler-skip decorator. In native-tests.yml under
  shell=powershell/windows-2022, before the existing fixed-image observation step,
  run exactly:
  `python -X utf8 tests/test_native_fixed_image_observation_contract.py FixedImageWindowsPathBridgeContracts.test_nonascii_bridge_uses_windows_framework -v`.
  It invokes the fixed bridge with the exact Windows PowerShell 5.1 executable
  under SystemRoot, forces changed non-ASCII case units, asserts an actual bridge
  match and records runtime/host identity. Missing bridge/runtime must fail rather
  than skip on Windows. General non-Windows discovery may mark only this Windows
  execution assertion unavailable; Linux compilation cannot discharge it.
  Add `test_unavailable_exact_comparison_rejects_pass_summary_without_require_pass`:
  unavailable bridge rejects an otherwise valid PASS summary with require_pass
  false and true, while a consistent affected-case FAIL/UNKNOWN plus FAIL summary
  is diagnostics only.
- [x] Witness old validator/corpus failures, extract the shared function and add the
  bounded fixed bridge plus portable safe subset. Keep raw paths and reject rather
  than normalize; do not introduce a public launch path or native API.
- [x] Run the fixed-image Python/managed module and PowerShell parse checks. Review
  exact UTF-16 counts/Cc range and comparison host identification. Record Windows
  bridge execution pending until the exact Windows assertion above is actually
  observed. Carry this gate into every later task/checkpoint until satisfied;
  later managed passes cannot erase it or stand in for the native runtime.

### Task 2C: Make file ownership exclusively transferable

**Status at 6a164db:** Source implementation and limited native/build proof accepted;
overall checkpoint blocked by the failed payload-continuation Prepare, with
Task 2D paused at that time. The later historical fc6abad prerequisite decision
below allowed test-only 2D to resume. The checked 2C items cover source and
managed recording-call behavior plus preserved standalone native file/probe
forwarding, not completed
native composition. See the [partial execution record](../EXECUTION-2026-11-11-exclusive-image-ownership-partial.md).

**Files:** Modify `NativeFixedImageIdentity.cs`, `NativeFixedImageIdentityTests.cs`,
`NativeFixedImageIdentityNativeTests.cs`, `check_native_fixed_image_observation.ps1`,
`test_native_fixed_image_observation_contract.py`.

**Consumes:** Task 2B path function; Task 2A genuine expectations.
**Produces:** `FixedImageCallDomain` and `IFixedImageNativeCalls` matching all
file/probe entry signatures/domain in the design; native implementation forwards to existing interop. `ClaimForComposition()`
returns the nested sealed CompositionLease once. Implement its ownership,
preparation, probe and release members here; BindBinaryLaunch/FixedImageLaunchBinding
are explicitly deferred to 2D after its shared formatter extraction. No temporary
command formatter is added in 2C. Facade mutations are permanently disabled after claim. Private native handle never leaves the context.
`FixedFixtureImage.CreateForRecording(IFixedImageNativeCalls calls,
FixedImageCallDomain domain)` accepts only recording calls/domain, never path or
expectation overrides. `RunInjectedOwners(byte[] pristineBytes)` receives bytes
from the helper's pristine child and validates them against the real embedded
expectation before supplying them through fake ReadFile. The image runner must
actually invoke this integer-returning method with verified pristine bytes, before
negative setup, in both managed-only and native paths, and reject nonzero return.

- [x] Implement managed `ClaimRejectsPreparedReleasedAndReused`,
  `ConcurrentClaimHasOneWinner`, `TransferredFacadeCannotPrepareProbeOrRelease`,
  `ReadyRequiresLiveUnclosedKnownHandle`, and `UnopenedReleasePreventsLaterClaim`.
  Assert no native calls during claim/rejection and a single irreversible winner.
- [x] Implement `RealFileOwnerUsesOnlyInjectedCalls`: prepare/hash/probes/release use
  the actual image owner with fake calls, including partial reads, EOF bounds,
  failed/open-unavailable/read-unavailable/probe-unknown and close FALSE/unavailable.
  Assert exact call order/handle, readiness revocation, no retry and retained owners.
  Keep the existing pure ledgers, but do not substitute them for this coverage.
  Add `test_runner_executes_injected_owner_contracts`: execute the image runner
  -ManagedOnly and require exactly one `PASS fixed image injected owners` marker,
  emitted only by the invoked method after its actual owner/fake-call assertions.
- [x] Add locked use-state transitions, capability binding and native adapters
  without changing the accepted file-observation algorithm. Verify behavior with
  runner-invocation/readiness failure witnesses and later weakened-guard controls.
  Both standalone/lease operations call shared private implementations. Add no
  arbitrary filename/digest setters, raw-handle access or public path getter.
- [x] Run fixed-image managed/validator tests. Review that standalone file-only
  Main still releases only its own nontransferred image and schema-1 evidence is
  unchanged; a composed Main must never inherit that unconditional finally close.

Witness history: the initial runner invocation and actual-owner readiness
assertions failed before their corrections. Later weakened-guard controls failed
at the named claim/facade/readiness/native-boundary assertions; these establish
regression sensitivity, not six separate original pre-implementation RED runs.
Both actual Windows runner logs now contain one injected-owner PASS before native
case output; exact runner source places the invocation before negative setup.
The claims use recording calls. The four real native file-only cases exercise
the forwarding adapter without transferring the image into a process owner.

### Task 2D: Compose the existing Binary owner and real decisions

**Current source/managed status:** All six items below are complete and covered
by independent whole-composition source review. Checked items prove source and
actual-method recording behavior only, not native CreateProcess/query/exit,
overlapped I/O or CloseHandle results. Fresh Windows/native acceptance remains
pending under 2E; this status does not alter the historical fc6abad prerequisites
or 6a164db failure/pause.

**Files:** Create `NativeFixedImageComposition.cs`,
`NativeFixedImageCompositionTests.cs`, `NativeFixedFixtureCommand.cs`; modify
`NativeFixedImageIdentity.cs` for deferred lease command binding,
`NativeChildCaptureNative.cs` and
all three runners/four direct Python owner compile lists as one dependency change.
Keep all existing child/sentinel/pipe/environment sources and assertions.

**Consumes:** Task 2C unused context/capability; Task 2B path comparator; Task 2A
build record and checked generated source.
**Produces:** `ChildCaptureOwner(FixedFixtureImage image)` (Binary only) and
internal `ChildCaptureOwner(FixedFixtureImage image, FixedImageCompositionBindings bindings)`,
with the same actual constructor/claim decisions;
`IChildCaptureProcessCalls`/`IChildCaptureFlow` signatures from the design,
`PrepareImageOnce()`, `ObserveProcessImageOnce()` and real `ObserveExit()`/`Release()`
ledgers. Extract the current inline command construction exactly once as
`FixedFixtureCommand.Format(string image,string scenario,long candidate,string token)
-> StringBuilder` in NativeFixedFixtureCommand.cs, preserving legacy command bytes.
Only then implement the lease's BindBinaryLaunch/FixedImageLaunchBinding; both it
and legacy Launch consume that shared formatter. Every image/owner consumer gains
this pure formatter source in 2D, while the four-source child remains independent.
`FixedImageCompositionTestRig.CreateOwner()` supplies one inseparable fake
image/process/flow/sentinel domain for managed tests, with no native selector. The new
`NativeFixedImageCompositionTests.RunManaged(byte[] pristineBytes)` is invoked
from a managed consumer built/loaded by the image runner; its full owner sources
are explicit and distinct from the four child sources. Genuine pristine build
bytes are verified and fed through fake ReadFile, never a digest override.
Default constructors always install native adapters. The constructor claims last,
without native calls; legacy constructor signatures/allowed scenarios stay closed.

- [x] Write failing `RealConstructorClaimsOnce`, `RealRunRefusesBeforeTransportOrCreate`
  (missing/size/digest/probe failures), and `RealRunIsOneShot`. Assert zero
  Proof.BeforeCreate/CreateCalls/query entries on every preflight refusal, no
  transport setup, and actual checked image resolution where permitted.
- [x] Write `RealLaunchUsesFixedBindingAndOriginalHandles`: same existing create
  method/flags/allowlist, one create, no second FileStream lease in composed mode,
  exact query Original.Process/flags 0/capacity 32768, never thread/PID substitute.
  Add `SharedCommandFormatterPreservesLegacyBytes`: all existing scenario strings,
  quoted paths/spaces, invariant decimal candidates and tokens produce byte-for-byte
  the original inline command; the composed Binary binding calls that same formatter.
  Assert there is no second formatter or temporary 2C command-construction body.
- [x] Write `QueryDiagnosticFailureStillClosesWritersPumpsAndReleases` for FALSE,
  unavailable, malformed/truncated/unsupported and valid-but-different paths.
  The recording flow feeds capture/EOF events and invokes real exit observation;
  writer close, sentinel inspection (including injected wait) and recovery forward
  to the real methods, with zero real transport/allocation handles;
  assert the actual Run trace continues through writer close, pump, sentinel,
  Refresh and Release, with sticky UNKNOWN even after successful image release.
- [x] Write `UnknownCreateAndInvalidOriginalsRetainWithoutQuery`,
  `UnavailableExitDoesNotFabricateWaitZero`, `ImageCloseFailureRetainsWholeOwner`,
  and `MixedNativeAndRecordingDomainsAreRejected`. Assert exact unavailable states,
  actual wait returns including 258/0xffffffff, no speculative close/retry, no fake
  process close through PipeNative, and no synthetic pipe/unmanaged-slot handles.
- [x] Witness failures, implement shared decisions/adapters and immutable ledgers.
  The flow delegates side effects only; existing Run owns every branch and existing
  Release enforces every old gate plus both EOFs for known-success composed
  launches before adding checked image release. No duplicate
  launcher/lifecycle model, PID reopen, CREATE_SUSPENDED or production change.
- [x] Run the three Python modules plus managed composition tests with genuine
  expectations. Review every reachable downstream native boundary for recording
  handles. Audit a known successful query fault separately from uncertain create;
  refuse 2E if either can bypass drainage or close an unresolved acquisition.

### Task 2E: Prove composed evidence and full Binary behavior

**Current source/managed status:** The first five items are complete, including
actual schema-2 validator/status-guard integration. Independent whole-composition
source review is complete with no open source findings. Those checks are source/
managed proof only. The last two items remain unchecked: no new exact-source
Windows/native execution or independent actual-artifact acceptance exists.

**Files:** Create `NativeFixedImageCompositionNativeTests.cs`,
`check_native_fixed_image_composition.ps1`; modify `NativeFixedImageIdentity.cs`
(stage-specific evidence serialization), `NativeFixedImageComposition.cs`,
`NativeFixedImageCompositionTests.cs`, `NativeChildCaptureNativeTests.cs`
(AssertCase visibility only), `test_native_fixed_image_observation_contract.py`,
source-list contracts and `.github/workflows/native-tests.yml` (additional composed
source triggers and separate composed step/text artifact; retain helper/path bridge
triggers and the Windows bridge assertion already introduced in 2A/2B). Preserve file-only execution/artifact too.

**Consumes:** Accepted 2A-2D interfaces; existing full Binary AssertCase, old nine/
three assertion sets and schema-1 file-only fields.
**Produces:** Schema-2/stage=composed bounded records exactly as the design matrix;
`validate_records(..., expected_stage='file-only', path_comparer=None)` and
`validate_evidence` with the same parameters plus require_pass. CLI
`--expected-stage composed` is compulsory in both composed runner validation calls;
old runner pins file-only. New native Main has no arguments and a compile-time
allowlisted case constant; new runner accepts ManagedOnly/EvidenceDirectory only.

- [x] Write failing `test_composed_stage_rejects_file_only_and_mixed_schema`,
  `test_composed_failure_matrix_nullability_and_owner_consistency`,
  `test_composed_retained_owner_stops_prefix`, and
  `test_composed_binary_assertions_are_complete`. Use the real C# serializer on
  recording-rig executions, not only handwritten JSON. Mutate each new field/state,
  including a fake wait=0, missing capture, discarded/hash/EOF/fairness mismatch,
  create_calls>1, query-after-zero-create, unavailable exact comparison with a PASS
  summary even when require_pass=False, released image with unknown creation,
  owner-released with image retained, and continued cases after a retained owner.
- [x] Witness failures, implement the separate exact schema and strict stage pin.
  Every design-matrix row gets a managed serialized diagnostic test; only the
  four expected native cases may PASS. Unavailable values stay null. Neither
  schema-1 acceptance nor synthetic records count as actual composed evidence.
- [x] Implement four isolated fixed harness builds using the shared pristine
  expectation. Only after all builds, prepare matching/same-size-corrupt/appended/
  absent copies in that order; never execute either corrupt copy. Each Main roots
  the real owner before Run, checks the expected refusal or calls unchanged full
  Binary AssertCase, reports snapshots and keeps unresolved roots. No unconditional
  transferred-image finally release. Exit 2 means any composed/file/probe owner
  remains retained; runner stops later cases and emits the attempted FAIL prefix.
- [x] Keep old native nine capture/three environment/four file-only suites intact.
  The positive composed assertion must include the design's exact Binary lengths,
  hashes, PVC2 exclusion, independent sentinel, both EOFs, terminal/released slots,
  fairness, exit 0, one create and one-shot refusal, plus matching image query and
  checked file release. No reduced assertion helper or UNKNOWN success exception.
- [x] Run the full managed/source suite, active-tree/whitespace checks, C# 5/x64
  warnings-as-errors and PowerShell/workflow parse checks against the final implementation tree.
  Confirm new runner/helper scripts stay ASCII-safe for Windows PowerShell 5.1.
- [ ] On separately permitted disposable/hosted Windows, execute all four runners
  (old capture/environment/file-only plus new composed), preserve actual logs and
  bounded artifacts, and validate the exact-source records in their explicit modes.
  Record actual runtime/path-comparison host. Verify the unchanged six-minute
  workflow budget from observed execution; do not raise it or drop gates silently.
- [ ] Obtain independent actual exact-source artifact review, including
  original-handle query, all four new cases, old nine/three/four suites, zero-create
  negatives, full Binary checks and every retained-owner failure contract.
  Independent code/source review is complete; this checkbox remains pending for
  actual Windows artifacts. Native evidence stays pending until observed;
  publication is a separate branch authorization. No merge/release or user-host
  safety claim follows from this work.

**Managed commands for the subtask cycles:**

- `python -X utf8 -m unittest discover -s tests -p test_native_child_capture_contract.py -v`
- `python -X utf8 -m unittest discover -s tests -p test_native_launch_environment_contract.py -v`
- `python -X utf8 -m unittest discover -s tests -p test_native_fixed_image_observation_contract.py -v`
- Final: `python -X utf8 -m unittest discover -s tests -v`, then `git diff --check`
  and the repository's active-tree gate. A failure from unavailable official refs/
  compiler is a prerequisite blocker, not the required TDD behavioral failure.

The completed source/managed stages do not advance native acceptance past its
separate execution/artifact gates. Contributions remain on the Draft branch;
publication and hosted execution require their own authorization.

## Current source-only composition checkpoint; native acceptance pending

The checked test-only implementation composes fixed Binary mode into the existing
owner lifecycle, with one shared command formatter and real original-handle
query/exit/close ledgers. Strict file-only/schema-1 and composed/schema-2 modes
validate exact states/nullability, every image-close entry's prerequisites,
one-shot snapshots and sticky UNKNOWN. Conservative Binary accounting requires
enough data and separate EOF completions plus later fair read visits; it does not
invent native activity or require pending+immediate to equal issued.

The final managed/source suite ran **449 total: 442 passed, seven expected
platform skips**. The covering fixed-image module passed 53 of 54 with one expected
Windows-only skip. All **41 real managed serializer rows remain FAIL diagnostics**,
with zero native pipe rounds/reads/visits and no native overlapped I/O. Plausible
synthetic PASS records are validator fixtures only. Independent whole-composition
source review is complete with no open source findings; this supports separately
authorized Draft publication and fresh exact-source acceptance CI, not native
acceptance. No new exact-source Windows/native CI has run.

Next gates are actual old nine capture/three environment/four file-only and four
new composed cases, unchanged full Binary checks, strict explicit validator modes,
actual Windows PowerShell 5.1/.NET Framework >=4.8 host/Unicode comparison and
observed completion within the unchanged six-minute native job budget, followed by
independent actual-artifact acceptance. No arbitrary launcher, production wiring/
image admission or recovery authority is added. User Windows 10/11, UAC, VM,
driver/service, workstation, merge and release acceptance remain outside this
harmless fixture checkpoint. Earlier source successes do not explain or repair
the unknown historical 6a164db failure or supply its absent teardown proof.

## Historical Task 1 verification checkpoint

Task 1 is test-only accepted at published source
`33447ae2ff048230675c05c72509857d252fceee`, tree
`b88bc27ebaf4693571e3f3505c6d3404962d7ab3`. Independent review accepted actual
native PR results at synthetic merge
`7f66505650b282efcff8fb08841619c03ec9211b`, with the same tree: four image cases,
nine baseline cases and three environment cases passed. Both hosted Linux jobs
successfully provisioned the pinned reference pack and ran 392 tests with six
unchanged platform skips. All five naturally triggered workflows passed on
attempt 1, with no rerun; there is no native PUSH run for this source. See the
[successor execution record](../EXECUTION-2026-11-11-net48-reference-provisioning.md).

The earlier `b2229c5` [partial record](../EXECUTION-2026-11-11-native-fixed-image-file-only.md)
remains eight successes and three failures. At that checkpoint Task 2 was
unimplemented and still required separate composition review and numeric sentinel
diagnostic hardening. The exact-source file-only prerequisite is satisfied for Task 1; it is not whole-product readiness, privileged admission or release
approval.

At this historical checkpoint Task 1 validators accepted only schema=1/
stage=file-only; schema=2/stage=composed was unavailable until separately reviewed
Task 2 implementation. Current source integration is recorded above, not native
acceptance retroactively attributed to this source.

## Historical source 5190564 planning checkpoint

The later source `519056432b4d9bd045140d2ba2bbe924e5c135e9`, tree
`45d21240a2b93e79f69b7a0c415d34ed7acdd31f`, has independently accepted actual
native push 43101335942 and same-tree PR 43101344284 artifacts after query-only
sentinel hardening. Each retains all nine capture, three environment and four
file-only image cases; both Linux jobs ran 403 tests with six unchanged platform
skips. The final independently reconciled inventory has all eleven naturally
triggered workflows successful on attempt 1 (eight push, three PR), including
private-payload continuation 43101335826. The verified
[sentinel execution record](../EXECUTION-2026-11-11-native-sentinel-observation.md)
was committed locally as `31255f3`; the published tested source remains `5190564`.
Earlier partial results remain unchanged. The exact changed-source native
prerequisite is satisfied. Composition remains unimplemented and this revision
resolves planning preflight only. Independent composition review remains required
before the next implementation stage. Contributions remain on the Draft branch;
native execution/publication and exact-source acceptance retain separate review gates.

## Historical accepted 98bec8f build/path checkpoint; next gate then 2C

Published source
[`98bec8f6fb035b90156b02fec8c63e9278deb010`](https://github.com/zlocorp/Portable-VirtualBox/commit/98bec8f6fb035b90156b02fec8c63e9278deb010),
tree `c92ed011a8097b7c135d06f75585ad45b4c72a9a`, includes only the reviewed
2A–2B implementation and scoped host-frame correction. All eleven natural
workflows passed on attempt 1 (eight push, three PR), without reruns. Native push
43113061248 checked out that exact source. Native PR 43113074200 checked out
synthetic merge `473074410cedce904af24bb03a295a12d2ca9a51`, independently verified
to have the same tree. Both actual artifact sets preserve all nine capture,
three environment and four file-only image cases.

Both native jobs executed the named Windows Framework bridge assertion, not a
skip: changed `C:\é` versus `C:\É` returned true through the fixed bridge,
under PowerShell 5.1/Desktop, observed Framework Release 533509, CLR
4.0.30319.42000/mscorlib. The minimum is Framework >=4.8/Release >=528040, not a
claim of exactly 4.8.0. Hosted Windows Server 2022 evidence does not prove user
Windows 10/11. The real-runtime gate is satisfied only for this source.

Earlier local Task 2B broad coverage was 421 tests/seven skips. The final
host-frame correction passed six bridge tests and 33 focused image tests/one
skip, not another local full suite. Both actual hosted Linux full suites now
pass **423 tests/seven skips**, including both new host-frame regressions and
successful pinned net48 provisioning. Exact log proof, ZIP hashes and the full
run ledger are in the [execution record](../EXECUTION-2026-11-11-fixed-fixture-build-paths.md).

Only Tasks **2A–2B** were accepted at that source. Tasks **2C–2E were unfinished**;
their checkboxes were then unchanged. Task 2E still needed to integrate the reusable
path-comparison guard into the actual stage-aware composed-artifact validator.
Schema 1 remains file-only and cannot certify schema 2. Later ownership/composition
edits require independent review and their own changed-source native evidence. No new primary-host,
production, merge or release permission is conferred by this checkpoint.

## Historical partial 6a164db ownership checkpoint; 2D paused

Published source `6a164dbdc14bf5d4d6ddadb072d7f7586f8560ff`, tree
`e8ebd3522f130e7c818148d32136a65112d97e92`, satisfies the reviewed 2C source and
limited native/build requirements. Native PUSH 43117916926 checks out the exact
source; native PR 43117927011 checks out synthetic merge
`9a004fbba550a1e33c87b02dd7ab0ae8fd16fd26` with the same tree. Ten native ZIPs
pass size/digest/CRC and actual-log checks. Both Linux suites pass 425 tests/seven
skips. Both real Windows bridge assertions execute under PowerShell 5.1/Desktop,
observed Framework Release 533509 and CLR 4.0.30319.42000/mscorlib; the minimum
remains Framework >=4.8/Release >=528040, not exact 4.8.0 or user-Windows proof.

The complete natural inventory is **10 successes and one failure, all attempt 1**.
Payload continuation 43117917218 fails during first Prepare after observed VBoxSup
staging/start, before any controlled interruption or continuation. The expected
SDS key is absent after a success-like process result; the helper journal is
incomplete and zero continuation cases complete. No verified teardown or final
data-preservation result exists. The underlying cause is unknown; ambiguous
partial recovery remains refused. Do not infer cleanup from job teardown.

**At 6a164db the overall checkpoint remained blocked and Task 2D was paused.** No
later success may overwrite this failure or claim its unknown cause resolved.
The later fc6abad decision below accepted new source-specific prerequisites and
permitted resuming harmless test-only 2D. At those historical sources Task 2D
command/binding/process work and Task 2E schema-2 validator/status-guard/native
integration were unchecked. Current source/managed progress above is separate
from still-pending native acceptance. Contributions remain on the Draft branch.
No production, primary-host, merge or release authority follows. See the
[partial execution record](../EXECUTION-2026-11-11-exclusive-image-ownership-partial.md).

## Historical fc6abad SDS prerequisite checkpoint; test-only 2D could resume

Source `fc6abadde89feda0c86a741a4e21fe2afabd0976`, tree
`6fd4627bcef4c3769858c29aa5c60323e2479fdd`, has accepted independent source,
native/build, system/payload and unsigned ALPHA file/build reviews. All twelve
natural workflows pass on attempt 1 (nine push, three PR), without manual dispatch,
reruns or assertion weakening. Native push checks out the head; PR checks out
same-tree synthetic merge `55d3cc09167c0da68c50082deac37d9ac998fb39`.

Actual Windows PowerShell 5.1 managed fixtures test the original bodies with
substituted effects, 47 Prepare cases, bounded renderer/writer and collector
refusals. Both native runs retain nine capture/three environment/four standalone
file-only suites and execute the real Framework bridge: Release 533509, minimum
528040/Framework >=4.8, on Server 2022 rather than Windows 10/11. Both Linux full
suites run 430 total/423 passed/seven skipped. Real protected-worker output has
16 diagnostic pairs with measured SDS exit 0; all nine payload continuations
complete with preserved original evidence and VM sentinel. Registry comparison
against the requested path is not launched-image identity, and no new system
query, retry, cleanup authority or production lifetime repair is introduced.
Exact runs, artifacts, package resources/pins and remaining limits are in the
[SDS execution record](../EXECUTION-2026-11-12-sds-observation-diagnostics.md).

**At fc6abad the changed-source diagnostic/native prerequisite was accepted;
test-only Task 2D could resume and was still unimplemented.** That next-stage
ruling did not rewrite the earlier audits' pause or the 6a164db failure. Harmless
fixture work could proceed on its own reviewed prerequisites while the historical
registration cause remained unknown and ambiguous production recovery stayed
refused. Task 2D implementation/review and Task 2E native composition, actual
schema-2 validator/status-guard integration and whole-composition review were
still required then; all 2D/2E checkboxes were unchecked at that source. Current
checkboxes above record later source/managed proof only. No production integration,
user-Windows, merge or release authority follows. A subsequent review of the six
captured launcher PNGs found no blocking clipping/overlap/Cyrillic defect, with
byte-identical Russian returns and 16 actually measured Button captions per view
(25 JSON controls total). That narrow visual result is not workstation/DPI/Oracle/
UAC/portability acceptance; two minor wording suggestions remain unimplemented.
ALPHA packaging is not runtime acceptance.
