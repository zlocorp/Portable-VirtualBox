# Exact Sentinel Observation Implementation Plan

> Proposal only. Independent preflight review is required before implementation.
> Execute test-first, with independent review between the pure and native stages.
> This document grants no publication, primary-host execution, merge or release.

**Goal:** Replace the fixed child's mutating numeric probe with exact-object-aware,
query-only exclusion while preserving existing capture and environment contracts.
**Architecture:** First add a pure PVC2 protocol, strict token handling and
one-shot query/close state machine exercised through a fake API. Then add the
Windows adapter and compose it with the existing parent owner and fixed child.
**Tech Stack:** C# 5, x64, .NET Framework 4.8, Windows PowerShell 5.1, Python unittest.
**Spec:** [Exact sentinel observation](../designs/native-sentinel-observation.md).

## Global constraints

- Native test-only minimum: Windows 10 / Windows Server 2016. Production support
  does not change. The existing hosted native runner is Windows Server 2022.
- Only the owned named reference may be closed. Never mutate, wait on, duplicate
  or close the borrowed candidate. No arbitrary native collision or race cases.
- Preserve nine capture and three environment purposes, exact three-handle
  inheritance list, counts, EOF/exit/terminal/close proofs and both JSONL schemas.
- PVC2 remains eight bytes; Empty emits none. Never represent semantic exclusion
  as the old FALSE/error-6 native result.
- UNKNOWN is sticky; missing/failed native observations and close outcomes never
  become known success through a retry or process teardown.
- No production edits or changes to `NativePipeTransport*`. No executable, command,
  environment, object-name or evidence inputs supplied by a runner's caller.
- Keep concurrent prerequisite provisioning separate. This plan does not require
  edits to `.github/workflows/ci.yml`, `BUILDING.md` or toolchain provisioning files.

## Review focus

1. A newly opened reference uses the candidate number: classify its allocation,
   not inheritance; exercise Task 1's deterministic fake table, not native churn.
2. A candidate changes after a valid query: FALSE/error 6 during comparison remains
   UNKNOWN, with no retry. Exercise in Task 1.
3. Stale last error or an unsupported comparison API: no FALSE result may pass
   without its required known error. Test fake results in Task 1 and adapter
   capture/availability paths in Task 2.
4. An existing named event or failed/unavailable reference close: never claim
   freshness or exclusion. Test close states in Task 1 and parent freshness in Task 2.
5. A missed compile path or reused expectation literal: compile the child through
   all three runners, update the existing independent payload helper, and test
   all dependency lists and exact PVC2 hashes in Task 2.

## File and compile-source map

**Create:**
- `tests/windows/NativeSentinelObservation.cs`: the actual pure child argument
  parser, token/protocol definitions, query interface and one-shot ownership state.
- `tests/windows/NativeSentinelObservationNative.cs`: fixed Windows adapters and
  narrow raw-call boundaries, with no general launcher or target selection.
- `tests/windows/NativeSentinelObservationNativeTests.cs`: recording raw-call
  fakes exercising the real adapter and the real parent's sentinel methods,
  exposed through `RunManaged()` with no actual native calls.

**Modify behavior/tests:**
- `tests/windows/NativeChildCaptureTests.cs`: deterministic pure query-state,
  token, byte-contract and close-ownership tests in the existing managed entry.
- `tests/windows/NativeCaptureFixtureChild.cs`: third token argument, observation
  adapter, PVC2 output and genuinely empty Empty branch; remove `SetEvent`.
- `tests/windows/NativeChildCaptureNative.cs`: fresh retained named sentinel,
  fixed command token and strict PVC2 inspection. Keep existing owner lifecycle.
- `tests/windows/NativeChildCaptureNativeTests.cs`: update the pure
  `Expected(int length,int seed,bool header)` literal to PVC2; retain all native
  assertions and independent body generation. Do not share the child's encoder
  as the expected-hash oracle.
- `tests/test_native_child_capture_contract.py`: actual managed behavioral tests,
  independent byte/hash expectations and its serializer compilation list.
- `tests/test_native_launch_environment_contract.py`: both embedded compilation
  lists and integration checks. Preserve its PVE1 fixture and JSON schema.

**Update every affected compile source list:**
1. `tests/windows/check_native_child_capture.ps1`:
   - Task 1 `Invoke-ManagedContracts`: add `NativeSentinelObservation.cs`.
   - Task 2 `Invoke-ManagedContracts`: compile the full parent/native-test source
     set below plus all three new sources, and invoke both
     `NativeChildCaptureTests.RunManaged()` and
     `NativeSentinelObservationNativeTests.RunManaged()`. This host must contain
     the real adapter and `ChildCaptureOwner`, not just their high-level fakes.
   - Child compilation: add the pure and native adapter sources, not adapter tests, beside
     `NativeCaptureFixtureChild.cs` and `NativeLaunchEnvironmentObservation.cs`.
   - Parent/native-test `$sources`: add the pure source in Task 1, then both native
     source and native-adapter test source in Task 2. The existing full set is
     `NativePipeTransport.cs`, `NativePipeTransportTests.cs`,
     `NativePipeTransportNative.cs`, `NativeChildCapture.cs`,
     `NativeChildCaptureTests.cs`, `NativeChildCaptureNative.cs`,
     `NativeChildCaptureNativeTests.cs`, `NativeLaunchEnvironment.cs` and
     `NativeLaunchEnvironmentNative.cs`; retain all dependencies.
2. `tests/windows/check_native_launch_environment.ps1`:
   - Shared parent `$sourceNames`, used by managed and native compilation: add
     both `NativeSentinelObservation.cs` and `NativeSentinelObservationNative.cs`,
     because the real parent now consumes the native-call boundary.
   - Child compilation: add the pure and native adapter sources, not adapter tests.
3. `tests/windows/check_native_fixed_image_observation.ps1`:
   - Pristine-child `Compile-Fixed` invocation: add pure and native adapter sources, including
     the managed-only C#5/net48 compilation route.
   - Do not add them to the four file-only harness source lists unnecessarily;
     those harnesses do not reference or run the child observation component.
4. `tests/test_native_child_capture_contract.py`:
   - `test_native_report_serializer_matches_schema_without_native_calls`'s
     embedded `$sources`: add both pure and native adapter sources.
5. `tests/test_native_launch_environment_contract.py`:
   - `test_legacy_constructor_rejects_appended_mode_before_native_entry`'s
     embedded `$sources`: add both pure and native adapter sources.
   - The actual environment `Report` serializer test's embedded `$sources`:
     add both pure and native adapter sources.

**Other wiring/docs:**
- `.github/workflows/native-tests.yml`: add all three new source paths to the existing
  narrow push trigger; preserve existing steps, case counts and timeout.
- `docs/designs/native-child-capture.md` and
  `docs/designs/native-launch-environment.md`: update probe meaning/version and
  limits, without altering historical execution records.
- Update this proposal's verification checkpoint only with actual later results.

`NativeLaunchEnvironmentNativeTests.cs` can keep its byte-8 slicing and thresholds.
`tests/test_native_fixed_image_observation_contract.py` already verifies pristine
bytes and generated expectations; run it unchanged unless a new dependency-wiring
assertion is needed. `sample_records()` in the child Python validator is a schema
fixture with deliberately synthetic hashes, not a payload oracle; do not replace
those fields with claimed OS evidence. No other existing pure payload helper was
found that embeds PVC1 or needs a byte-contract change.

## Shared-file dependencies and sequential gates

| Shared file or interface | Task 1 responsibility | Task 2 dependency and gate |
| --- | --- | --- |
| `NativeSentinelObservation.cs` | Actual parser, immutable arguments, PVC2, query/close state and high-level seam | Consume reviewed interfaces; return for review before changing them |
| `NativeChildCaptureTests.cs` | Pure tests and fake high-level API only | Keep intact; below-adapter tests go in the separate native-adapter test file |
| `check_native_child_capture.ps1` | Add pure source to managed and parent-native compile sets | After Task 1 review, expand managed host to real adapter/parent and invoke its tests |
| `test_native_child_capture_contract.py` | Parser/state/wire tests | After Task 1 review, add real-adapter execution marker, compile dependencies and hash expectations |
| Parent, child, environment/file-only runner and serializer lists | No native behavior change | Task 2 only, after interface freeze; update all lists as one dependency change |

First complete this revised preflight review. Then implement and verify Task 1,
obtain independent review, and freeze its interfaces. Only then start Task 2;
do not edit shared files for both tasks concurrently. Task 2 must pass the real
adapter/parent managed tests before native child wiring is considered complete.
Final implementation review precedes separately authorized publication and normal
changed-source native observation. No gate can be satisfied by an unexecuted plan,
a skipped test or a run of the earlier source.

## Task 1: Pure protocol, token and query-state contracts

**Files:** create `NativeSentinelObservation.cs`; modify
`NativeChildCaptureTests.cs`, both the managed-only and parent-native source lists
in `check_native_child_capture.ps1`, and `test_native_child_capture_contract.py`.
No native adapter, child behavior or parent launch change in this stage.

**Interfaces:** `SentinelArguments.TryParse(string[] args,
out SentinelArguments parsed,out int rejectionExit)` is the sole pure parser.
Its private construction yields immutable `CaseName`, Int64 `Candidate` and
`Token`; it has no dependency on `CaptureCase`. Apply the exact allowlist, canonical
decimal/Int64 bound, token grammar and exit mapping in the design. Task 2 child
`Main` must consume this method and result directly, not duplicate their logic.

Internal `SentinelResult` has `Unknown=0`, `Excluded=1`,
`SameObject=2`. `SentinelProtocol.ReferenceName(string token)` validates/reconstructs
the exact fixed name; `Encode(SentinelResult result)` returns eight fresh bytes;
`IsExcluded(byte[] bytes,int count)` returns a Boolean after validating the captured
prefix without treating body bytes as part of the preamble. Construct a rooted
`SentinelObserver(SentinelArguments arguments)` before calling its one-shot
`SentinelObservation ObserveOnce(ISentinelQueryApi api)`. It owns its one acquired
reference, never the candidate. `SentinelObservation` exposes semantic result,
identity reason and separate `OpenOutcome/OpenError`,
`ProbeStage/ProbeOutcome/ProbeError` and `CloseOutcome/CloseError` fields defined in
the design. A close must never overwrite the identity reason or probe error.
Separate before-call and known-return states cover open, query/comparison and
close; unresolved reference ownership stays on the observer. The internal API
seam has these exact shapes:

- `IntPtr OpenReference(string name,out uint error)`;
- `bool QueryHandle(IntPtr handle,out uint flags,out uint error)`;
- `bool CompareHandles(IntPtr first,IntPtr second,out uint error)`;
- `bool CloseReference(IntPtr reference,out uint error)`.

The adapter reports zero on known success, actual immediately captured errors on
known failure, and exceptions/unavailable returns as unknown, not invented error
numbers. Success-path zero is normalized API output, not captured last-error
evidence; the corresponding observation error is null. Native behavior is
unavailable in Task 1. Injected fake implementations
must exercise the same observer that the child will use in Task 2.

- [ ] Add failing tests calling the actual `SentinelArguments.TryParse`: exactly
  three arguments, all ten ordinal case names including EnvironmentObservation,
  rejection of case variants, canonical decimal 1 and Int64.MaxValue, rejection
  of 0, leading zeroes, signs, whitespace, Unicode digits, 20 digits and
  9223372036854775808. Assert parsed=null and exact exits 90/91/92 on rejection.
- [ ] Add failing token tests for exact 32-character lowercase hexadecimal input;
  reject null, wrong length, uppercase, whitespace, separators, backslash, quote,
  NUL and non-ASCII input before any API call. Reject zero/negative/overflowed
  candidate input and extra child argument shapes through that same parser.
- [ ] Add failing wire tests for exact `[80,86,67,50,1,0,0,165]`, fresh byte arrays,
  invalid result values, truncation, PVC1, reserved bytes and marker changes.
  `IsExcluded` must require `8 <= count <= bytes.Length` and validate only the first
  eight bytes, because the capture also contains the body. Test all result values.
- [ ] Add deterministic fake-API tests for the spec's full sequence: successful
  reference self-comparison; invalid candidate/error 6; different/error 1656;
  exact same object; reference allocated at candidate; invalidation after query;
  unexpected/stale errors; unsuccessful self-comparison; unavailable returns;
  open failure; and successful, failed or unavailable close.
- [ ] Assert call order and arguments. Every accepted path requires one confirmed
  owned close; no candidate close, duplicate, signal, reset, wait or flag change
  exists. A repeated observation or close attempt is refused before another call.
  Model SAME with an unsignaled parent observation and ensure it still refuses.
  Pin different/error 1656 plus close failure/error 5 to two preserved errors and
  semantic UNKNOWN; pin SAME plus close uncertainty to preserved SAME reason and
  unavailable close, never EXCLUDED.
- [ ] Run `python -X utf8 -m unittest discover -s tests -p test_native_child_capture_contract.py -v`
  with PowerShell available and witness genuine failing behavioral assertions.
  A skipped managed runner or missing prerequisite is not the required RED/GREEN.
- [ ] Implement only the pure component and fake-backed contracts. Require
  EXCLUDED only after a permitted branch plus confirmed close; preserve actual
  branch/error facts and UNKNOWN without synthesizing native return values.
- [ ] Run that Python module and
  `pwsh -NoProfile -NonInteractive -File tests/windows/check_native_child_capture.ps1 -ManagedOnly`.
  Require the existing managed PASS message and no native-case evidence or child
  execution. Obtain independent review before native composition.

## Task 2: Named-reference adapter and existing-owner composition

**Files:** the remaining implementation, dependency, contract and documentation
files listed above. Preserve the Task 1 protocol/state interfaces.

**Consumes:** `SentinelProtocol` and the tested observer/API seam.
**Produces:** `NativeSentinelQueryApi(ISentinelQueryNativeCalls calls)` implementing
the four high-level operations with the real ordering. Raw query calls expose
`void ClearLastError()`, `uint CaptureLastError()`,
`IntPtr OpenEvent(uint access,bool inherit,string name)`,
`bool GetHandleInformation(IntPtr handle,out uint flags)`,
`bool CompareObjectHandles(IntPtr first,IntPtr second)` and
`bool CloseHandle(IntPtr handle)`.

`IFreshSentinelNativeCalls` exposes the same clear/capture/close methods plus
`IntPtr CreateEvent(IntPtr privateDescriptor,bool manualReset,bool initialState,
bool inherit,string name)` and
`bool SetHandleInformation(IntPtr handle,uint mask,uint flags)`. The real Create
implementation constructs the exact SECURITY_ATTRIBUTES from these arguments.
The fixed default parent uses the real implementation. An internal
`ChildCaptureOwner(CaptureCase scenario,IFreshSentinelNativeCalls calls)` overload
allows managed tests to construct the same owner with a fake boundary.

Real `Prepare` calls `PrepareFreshSentinel(IntPtr privateDescriptor)`;
real `Release` calls `CloseSentinel()`. Both helpers operate on the existing rooted
sentinel field and close proof, using the injected boundary. Real `Launch` checks
`SentinelReady` before any image-file or process operation, throwing
`InvalidOperationException("Fresh sentinel required")` when false. Existing
`ChildCaptureOwner.Run()` and the fixed child remain the sole launch/capture path.
No public runner inputs, alternate executable, arbitrary namespace or new artifact
fields are introduced by these internal test boundaries.

- [ ] Compile the real native adapter, real parent and recording low-level fakes
  in the expanded managed host above. Add failing tests that execute
  `NativeSentinelQueryApi`, rather than replace it with `ISentinelQueryApi` fakes.
  For each operation assert `clear -> native call -> immediate capture` on FALSE
  or NULL, with no intervening query; assert success does not read stale error.
  Parent Create must capture immediately even on non-NULL to detect error 183.
  Fake raw calls return or throw at exact boundaries; no fake handle reaches
  P/Invoke. Require the new managed adapter PASS marker from the Python runner test.
- [ ] Add failing adapter-contract tests for `OpenEventW` access `0x00100000`,
  noninheritance, exact reconstructed name, explicit last-error clearing/capture,
  Kernelbase comparison availability and close restricted to the owned reference.
  Model exceptions/unavailable outcomes rather than forcing native uncertainty.
- [ ] Execute the real parent's `PrepareFreshSentinel` and `CloseSentinel` with
  injected raw-call fakes. Add failing freshness tests for NULL creation, error 183
  with a returned handle, successful fresh creation and unavailable return.
  Refusal must precede inheritance changes. Assert exact Create arguments: private
  descriptor, manual=true, initial=false, inherit=false and reconstructed name.
  Only fresh success may call SetHandleInformation with mask=1, flags=1, and only
  its known TRUE may set SentinelReady. Assert known failure or unavailable flag
  return cannot set readiness. Repeated fresh preparation must refuse before any
  clear/create/flag call. Close entry must revoke readiness. Call the actual refused `Launch` and require its
  exact guard exception before files/process entry; CreateCalls stays zero.
  Checked cleanup may close only that newly returned owned handle; failed or
  unavailable close remains unresolved and a second CloseSentinel/Release path
  must not issue another close. Acquisition or error-capture uncertainty retains
  the rooted handle/unknown state and forbids launch. Do not call full Prepare or
  any successful Launch in managed tests.
- [ ] Add failing integration expectations for the three exact revised stdout
  hashes `e6a7f5deb30873c0`, `031381f5c4fbe740`, `c1f1accadf2339e9`; unchanged Empty
  hash `cbf29ce484222325`; unchanged body/total sizes and stderr hashes. Use an
  independent Python calculation and the existing C# pure `Expected` helper.
- [ ] Test that Empty makes no writes and maps completed exclusion to exit 0,
  all non-exclusion to 94. Nonempty SAME/UNKNOWN headers must fail despite correct
  body, normal exit and EOF. Keep the ordinary exception exit-93 behavior. Specify
  and check a child static observerRoot assigned before ObserveOnce; it remains
  rooted through Empty, successful output and exception returns. Main's outer
  finally may KeepAlive the root but cannot close, dispose, clear or retry it.
- [ ] Implement the small adapter and parent named creation using the already
  owned private DACL. Preserve acquisition/close return guards. Pass the generated
  token as the third fixed argument. Child Main calls the exact Task 1 parser and
  consumes its immutable result; remove its duplicate argument parsing. Do not
  accept arbitrary object names. Remove the child's `SetEvent` declaration and
  call; invoke the observer before output.
- [ ] Update `InspectSentinel` to accept only exact PVC2 or Empty's dedicated exit
  inference. Keep the independent parent `WaitForSingleObject(sentinel,0)==258`
  check, every native assertion, all fault sites and existing release rules.
- [ ] Update the independent `Expected` literal and all compile lists above. In
  the file-only runner, regenerate pristine-image expectations from completed new
  build bytes before negative copies; retain four file-only cases and no child run.
- [ ] Keep both JSON schemas, validator strictness and record bounds unchanged.
  Exercise the actual serializers on never-run owners and require failure-only
  diagnostics, not fabricated native success. Preserve byte-8 PVE1 parsing and
  the diagnostic-fault fragmentation test; do not touch environment field logic.
- [ ] Run the child, environment and fixed-image Python contract modules, then
  `python -X utf8 -m unittest discover -s tests -v`, PowerShell/YAML parse checks,
  C#5/x64 warnings-as-errors/net48 compilation through all three runners, the
  repository's active-tree check and `git diff --check`. Report prerequisites or
  platform skips honestly; never execute a generated Windows child on Linux.
- [ ] Independently review API contracts, inferred allocation classification,
  strict error-1656 policy, owned-only close, compile lists and unchanged 9+3 case
  purposes. No source publication until its separate authorization/review gate.
- [ ] Following authorized changed-source publication, inspect normal hosted CI
  observations for all nine capture, three environment and four image cases.
  Verify actual counts/hashes, EOF, exits, fault sites and release observations.
  Unexpected comparison errors remain UNKNOWN and require diagnosis, not widening
  acceptance, manufacturing collisions, longer timeouts or reruns for green.
- [ ] Record exact source and tested checkout, run/artifact links and digests,
  distinguishing push and synthetic-merge PR results. Preserve the original
  b2229c5 failure and explain that local managed passes were not native evidence.

## Verification checkpoint

Preflight review and the independent pure Task 1 source/interface review are
complete. Pure Task 1 is commit `f94362fc4a5d54909a620cac29cd6ca00cce6b23`;
its component and behavioral test source remain unchanged in Task 2.

Task 2's query-only native adapter, existing-owner fresh named event and fixed-child
PVC2 composition are implemented locally. On the Task 2 worktree based on
`c7f8326b39accdb43d3b22659ff17453655b95e6`, final local checks passed:

- Child, environment and file-only image Python modules: 32, 24 and 13 tests,
  respectively, with no skips in those modules.
- Full Python discovery: 403 tests, six existing Windows-only platform skips.
- C#5/x64/net48 warnings-as-errors compilation of the actual child, expanded
  managed host and parent/native source lists from both launch runners; the
  file-only runner also compiled its pristine child and four harnesses through
  its managed-only official-reference route. No generated Windows EXE ran locally.
- All 53 PowerShell files and 21 workflow YAML files parsed. Active-tree check,
  enforced source audit and whitespace checks passed.
- Real-method managed tests cover raw clear/call/capture ordering, unavailable
  returns, parent freshness/launch refusal and one-shot close ownership. Independent
  PVC2 stdout hashes match the stated constants; Empty and stderr hashes remain
  unchanged. The two JSONL schemas and all 9+3+4 case purposes are preserved.

Independent Task 2 source review and authorized changed-source Windows observation
remain pending. Local managed passes and compilation are not native evidence.
The original b2229c5 PR failure and same-source push success remain distinct;
neither they nor the published 33447ae checkpoint verify this new PVC2 behavior.
This task does not publish source, update PR #7, merge, release or run on a user host.
