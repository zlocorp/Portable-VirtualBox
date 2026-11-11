# Native Fixed-Image Observation Implementation Plan

> Execute task-by-task with TDD and independent review.
> Task 1 is test-only accepted; Task 2 remains a proposal.
> This document authorizes no new implementation, publication,
> production integration, merge, release or primary-host execution.

**Goal:** Observe a fixed harmless build image and refuse unexpected bytes before
native creation, without treating matching bytes as privileged admission.
**Architecture:** A sealed exact-native-file owner consumes build-generated
expectations. First verify it without a process; then opt into the existing
ChildCaptureOwner without duplicating launch/capture logic.
**Tech Stack:** C# 5 x64 .NET Framework 4.8, Windows PowerShell 5.1, Python unittest.
**Spec:** [Fixed-image observation](../designs/native-fixed-image-observation.md).

## Constraints and review focus

- Preserve all nine baseline and three environment cases and both artifact schemas.
- No external native-entry path/digest/manifest inputs and no arbitrary launcher.
- Keep generated expected bytes separate from runtime observations; missing/stale
  build input fails closed. Never regenerate after preparing a negative copy.
- Open/read/close unknown-return states are one-shot and retained; model these
  without creating real uncertain native operations.
- Same-length corruption must reach the hash comparison; appending tests only size.
- Process-image query uses only Original.Process; post-create failures still drain.
- Existing managed FileStream disposal does not become verified native close.

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

## Task 2: Opt-in existing-owner composition

**Modify:** `tests/windows/NativeChildCaptureNative.cs`, the Task 1 harness/tests,
`tests/windows/check_native_child_capture.ps1`,
`tests/windows/check_native_launch_environment.ps1`, affected compile contracts,
and `.github/workflows/native-tests.yml` only to extend Task 1 wiring with required
dependencies and composed observation. Reuse its separate bounded artifact contract.
Do not change the fixed child's behavior.

**Interface:** `ChildCaptureOwner(FixedFixtureImage)` selects existing Binary
behavior with a sealed unused image context. Legacy constructors remain unchanged.
Prepare the context before native creation; use its fixed application/root; query
only Original.Process after successful creation. Preserve existing capture slots
and environment semantics. Keep old evidence schemas intact.

- [ ] Write failing tests for null/reused context, preparation rejection before
  Proof.BeforeCreate/CreateCalls, and exact zero-create missing/digest/size cases.
  Keep negative copies isolated from every positive launch.
- [ ] Write tests for original-handle-only image query, query failure followed by
  normal retained-owner drainage, unknown-create retention, image-close failure,
  single-use Run refusal and sticky diagnostic UNKNOWN after successful release.
- [ ] Implement only the opt-in composition and checked image-release participation.
  No PID reopen, second launcher, CREATE_SUSPENDED or general executable input.
- [ ] Update all compile-source paths to include generated expectations without
  native placeholders. Run unchanged baseline and environment assertions/schema
  validation; inspect differences to ensure no weaker release or output checks.
- [ ] Extend separate evidence to prove positive process-path observation and the
  three zero-create refusals. Preserve raw path observations and fail unsupported
  path forms rather than silently normalizing or truncating them.
- [ ] Run the full Python suite, active-tree and whitespace checks, both old native
  runners and the new runner on permitted Windows. Recheck workflow/PowerShell
  parsing, C# 5/x64 warnings-as-errors and existing timeout budget.
- [ ] Independently review implementation and exact-source Windows artifacts.
  Require all nine baseline plus three environment cases and new image cases.
  Keep failed/unknown artifacts distinct and mark native evidence pending until
  actually observed. Publication requires its separate authorized branch process.

## Current verification checkpoint

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
remains eight successes and three failures. Task 2 is unimplemented and still
requires separate composition review after hardening the known numeric sentinel
diagnostic limitation. The exact-source file-only prerequisite is satisfied for
Task 1; it is not whole-product readiness, privileged admission or release
approval.

Task 1 validators accept only `stage=file-only`; `composed` validation remains unavailable until Task 2 passes its prerequisite gate.
