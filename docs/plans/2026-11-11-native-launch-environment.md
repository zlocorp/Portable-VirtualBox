# Native Launch Environment Implementation Plan

> Execute task-by-task with TDD and independent review. This document authorizes
> no production integration, merge, release or primary-host execution.

**Goal:** Observe an explicit bounded Unicode environment in the fixed harmless child.
**Architecture:** A pure codec and closed fixture policy feed the existing retained
native owner. Separate environment cases leave the nine baseline capture cases intact.
**Tech Stack:** C# 5 x64 .NET Framework 4.8, Windows PowerShell 5.1, Python unittest.
**Spec:** [Explicit launch environment](../designs/native-launch-environment.md).

## Constraints and review focus

- Preserve baseline source `50262c86658ce99453845a021786b781d68aae87` and its nine
  capture-case assertions; review its hosted evidence before extending it.
- Never modify production helper/worker source, existing pipe slots or release authority.
- Test-only fixed executable and enum-selected behavior; no arbitrary launch interface.
- Review duplicate names, invalid UTF-16, exact bounds, missing native return and
  uncertain release. Pin each with tests below, not just source-string assertions.
- A field called PASS includes expected fault behavior, never mutation authorization.

## Task 1: Pure bounded environment codec

**Create:** `tests/windows/NativeLaunchEnvironment.cs`,
`tests/windows/NativeLaunchEnvironmentTests.cs`,
`tests/test_native_launch_environment_contract.py`.

**Interface:** `EnvironmentBlockCodec.Encode(KeyValuePair<string,string>[] entries)`
returns new UTF-16LE bytes using the exact limits and rules in the spec. No OS calls.

- [ ] Add behavioral managed tests for sorted exact bytes, double terminator,
  empty input as exactly four zero bytes, empty value, Russian/supplementary text
  and equals within a value.
- [ ] Add rejection tests for null entries, invalid/empty/65-character names,
  case-insensitive duplicates, NUL and unpaired surrogates. Test 16 versus 17 entries,
  4,096 versus 4,097 value units, and exactly 16,384 versus 16,385 total block units.
- [ ] Make the Python test compile/run the managed harness with the existing net48
  toolchain convention; witness a failing behavioral assertion before implementation.
- [ ] Implement the codec, defensive copies and checked sizes; assert subsequent
  caller-array changes cannot change returned bytes. Witness GREEN.
- [ ] Run `python -X utf8 -m unittest discover -s tests -p test_native_launch_environment_contract.py -v`.
  Require behavioral passes; record toolchain/platform skips honestly. Review independently.

## Task 2: Closed policy and retained allocation

**Create:** `tests/windows/NativeLaunchEnvironmentNative.cs`.
**Modify:** the new managed tests/contracts from Task 1.

**Interfaces:** `FixedChildEnvironment.CreateForObservation()`, `CopyBytes()` and
`WindowsDirectory`; `EnvironmentAllocation.Prepare(byte[])`, `Pointer`,
`TryRelease(CreateEntryState createState)` and `ReleaseUncertain`, exactly as specified.
`CreateEntryState` is `NotEntered, EnteredReturnUnknown, ReturnedFalse, ReturnedTrue`.
The allocation has a one-shot state model testable without native memory calls.

- [ ] Test the policy's four exact keys and literal, and its rejection of unsuccessful,
  truncated or unsupported Windows-directory results through a test-only query adapter.
  Pin the single 260-WCHAR query, 3..259 result length and exact local-path grammar
  from the spec; both system entries must use the same successful result.
  The public-to-harness factory itself accepts no injected strings or environment map.
- [ ] Test allocate-before-create, pre-entry failure, known native FALSE, unknown return,
  repeat preparation/release refusal and release-entered-without-return retention.
  Independently test allocation/free entry states, unknown allocation retention and
  pre-call irreversible transitions. Test NotEntered versus EnteredReturnUnknown
  explicitly; synthetic results are confined to model tests, never real launch.
- [ ] Witness RED; implement bounded OS query, immutable policy and rooted unmanaged
  allocation with explicit release bookkeeping; witness GREEN.
- [ ] Extend the Python harness to compile these test-only types and exercise managed
  decisions. Inspect that no ambient variable supplies a trusted system value.
- [ ] Run the Task 1 command and independent review before native composition.

## Task 3: Native environment observation

**Modify:** `tests/windows/NativeChildCaptureNative.cs`,
`tests/windows/NativeCaptureFixtureChild.cs`.
**Create:** `tests/windows/NativeLaunchEnvironmentNativeTests.cs`,
`tests/windows/check_native_launch_environment.ps1`.
**Modify:** new Python contract tests and `.github/workflows/native-tests.yml`.

**Interfaces:** Keep the nine baseline values accepted by `ChildCaptureOwner(CaptureCase)`;
reject appended EnvironmentObservation and every invalid enum before setup. Add
`ChildCaptureOwner(FixedChildEnvironment)` selecting only the new
`CaptureCase.EnvironmentObservation`; preserve `Run()` and its one-shot ownership.
The new runner emits separate strict bounded `native-launch-environment.jsonl`
records with `mutation_authorized=false`. It must not change the nine-case baseline
report schema or existing artifact parser expectations.

- [ ] Write failing assertions for parent ambient sentinel present, child sentinel absent,
  exact explicit Unicode and directories, and present-but-empty variable. Specify the
  PVE1/version-1 record constants/parser from the spec together. Reject header,
  version, presence/reserved flags, UTF-16/NUL, odd/excess lengths, overflow,
  truncation and trailing data. Assert 16,384 record / 16,392 stdout byte bounds.
- [ ] Add fixed-child native enumeration and bounded allowlisted record generation.
  Test 32,768 scan units / 512 entries / 8,192 units per entry at and beyond bounds;
  include hidden drive entries, duplicates, invalid UTF-16, malformed/unterminated
  blocks, null/error and exhaustion. None may produce successful absence. Verify
  original-pointer FreeEnvironmentStringsW in finally and checked failure behavior.
- [ ] Test native sentinel restoration for absent, present-empty and nonempty initial
  states on normal and fault paths, independently re-enumerating after restoration.
  Do not use managed null/empty semantics. Serialize cases and stop on restore failure.
- [ ] Attach the prepared allocation before create, pass non-null pointer and flags
  `0x00080400`, retain allocation on unknown outcome, and integrate its release facts
  into the owner's all-resources-released result. Root every owner before native
  entry; stop new cases on unresolved ownership. Test direct CaptureCase constructor
  rejection before native setup. Do not change pipe-slot implementations.
- [ ] Add serial fixed environment scenarios for normal observation, post-create exception
  and evidence exception. Use `EnvironmentObservationFault { None, AfterCreate, Evidence }`
  and `ChildCaptureOwner(FixedChildEnvironment, EnvironmentObservationFault)` from the
  spec; injection is parent-side and never changes child command arguments.
  Evidence fault poisons only the diagnostic sink, never observation capture: test
  fragmented receives with sink failure before final fragment, then require the
  complete actual parsed observation and sticky UNKNOWN. Do not reuse CaptureFault's
  discard behavior. Fault cases still drain and observe lifetime independently;
  explicit resource release does not erase UNKNOWN.
- [ ] Test repeat Run refusal before native calls and compare the nine original cases'
  expectations unchanged. Run the original check_native_child_capture.ps1 as regression.
- [ ] Add only needed workflow path triggers, a separate hosted observation step and bounded
  text artifact. Reuse existing job timeout; no manual system-effect acceptance dispatch.
- [ ] Run local Python suite, active-tree and whitespace checks, C# 5/x64 warnings-as-errors
  compilation, and PowerShell/YAML parsing. Record native execution as pending until Windows runs.
- [ ] Independently review, then publish only through the existing approved branch process.
  Review exact-head hosted results and artifacts, including all nine baseline cases, before
  writing an execution record. Preserve failed/unknown evidence and do not infer release readiness.

## Task 4: Optional separate fixed-image admission

Not a dependency of Tasks 1-3. Schedule only after their observation is reviewed.

**Proposed new files:** `tests/windows/NativeFixedImageIdentity.cs` and
`tests/windows/NativeFixedImageIdentityTests.cs`; a separate design must settle the
build-generated digest source before implementation. No new production files.

- [ ] Define `FixedFixtureImage.OpenSibling()` with private construction and no path/digest
  parameters; expose held-stream SHA-256, native identity and resolved path as observations.
- [ ] Generate the expected child digest into test-harness build input, rather than trusting
  a caller-selected file; record build provenance and limitations from the spec.
- [ ] Test expected-digest mismatch/missing child refusal before create, held leaf write/delete
  sharing denial, and original-process-handle path observation. No malicious substitutions.
- [ ] Review ancestor/ACL/configuration/dependency and loaded-byte limitations explicitly;
  do not call matching disk bytes a complete execution trust boundary.

## Verification record

Tasks 1–3 have local implementation, managed RED/GREEN and independent review.
Hosted Windows environment observations and baseline runtime regression on the new
source remain pending. All 11 baseline workflows passed separately; that does not
verify this increment. See the local checkpoint below for its actual test results.

## Local implementation checkpoint (2026-11-11)

Tasks 1–3 are implemented in test-only code; Task 4 is not implemented. The nine
baseline cases, expected outputs and evidence schema are unchanged. Their compile
source lists gained the new dependencies only. Environment evidence is a separate
three-case, four-record maximum artifact and never grants mutation authority.

Witnessed assertion RED→GREEN for codec exact bytes, policy/path rejection,
one-shot preparation after release, native-block observation and free matching,
legacy constructor closure, diagnostic sink failure, and strict evidence mutation
rejection. Managed runs pass 372 codec and 73 policy assertions plus parser,
scan/free, fragmented-record and diagnostic Write/Flush/Length fault contracts.
Only environment mode requests 16-byte native reads, so its diagnostic failure is
observably before the final record fragment without relying on scheduling sleeps.

Local verification: 369 Python tests passed with six native-platform skips;
active-tree and whitespace checks passed; both PowerShell runners parsed; workflow
YAML parsed with the existing six-minute budget; the environment harness and fixed
child compiled as C# 5/x64/.NET Framework 4.8 with warnings as errors.

Independent implementation review found no remaining blockers and independently
reran all 24 environment contracts with PowerShell. Exact-head hosted Windows
observations are still pending. Local managed execution is not native Windows evidence. The native
sentinel absence/empty/nonempty restoration matrix, all three environment cases,
and all nine baseline regression cases must pass on hosted Windows before writing
an execution acceptance record. No production source, production helper semantics,
image-admission policy, release or merge authorization changed.

The artifact now includes independently decodable actual PVE1 bytes and the
separate OS-query directory expectation. Mutation tests reject forged observation
booleans when the actual Unicode, presence or directory fields differ. Both affected
Windows compiler runners explicitly use UTF-8 source decoding (`/codepage:65001`).
