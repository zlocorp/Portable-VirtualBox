# Native Launch Observation Implementation Plan

This plan records the implementation steps, independent review and exact-commit verification of the test-only experiment.

**Goal:** Replace hypothetical child-lifetime premises with bounded, test-only Windows observations.

**Architecture:** A fixed fixture and exact retained native handle provide observations, never authority. A held file-only recorder fails closed; managed contract tests run independently of Windows. Runtime IL metadata is diagnostic evidence.

**Tech Stack:** C# 5, x64 .NET Framework csc, PowerShell, Python unittest.

**Spec:** `docs/designs/native-launch-observation.md`.

## Global constraints

- Do not change production source, scripts, build or package inputs.
- No VBox/system effects, elevation, arbitrary launch, kill, suspension, shell or pipe redirection.
- Every observation decision has `mutation_authorized=false`; no PID adoption or retry authority.
- Preserve UNKNOWN after faults, timeout and poisoned evidence, even after genuine zero exit.
- Retain the process handle before metadata; drain to signal and read exit code before close.
- Keep real WAIT_FAILED explicitly unresolved; do not silently close a live handle.

## Review focus

- Post-native-success exceptions before any metadata must still drain the retained handle.
- A signal plus exit 259 must be accepted as genuine exit, not treated as live.
- Persistent wait failure must preserve unresolved handle/file state and fail the run.
- Acknowledgment must follow actual bounded write, flush and readback, without recorder repair.
- Exact loaded Framework metadata must not be described as universal control-flow attestation.

## Task 1: Record the protocol and test RED

Files: this plan, the design, `tests/test_native_launch_observation_contract.py`.

- [x] Add portable runner expectations before implementation.
- [x] Run focused unittest and witness three missing-runner assertion failures.
- [x] Add behavioral C# tests before the observer/recorder implementation and witness a protocol assertion fail.

## Task 2: Implement isolated observations

Files: `tests/windows/NativeLaunchObservationTests.cs`, focused companion sources,
`tests/windows/check_native_launch_observation.ps1`.

Interfaces: `NativeLaunchObservationTests.RunManaged()` executes no native calls;
`Main(string[])` accepts only native test execution. Internal attempt methods
consume only the fixed owned fixture and expose read-only diagnostic snapshots.

- [x] Implement and run actual recorder behavior, bounded evidence and sticky decisions.
- [x] Implement fixed-child native creation, identity checks, native wait and trusted draining.
- [x] Implement runtime inspection with raw bounded IL/token/branch evidence and unsupported status.
- [x] Run focused portable tests and C# 5 net48 reference compilation.

## Task 3: Wire and verify bounded CI evidence

Files: `.github/workflows/native-tests.yml`, one `docs/RELEASE-GATES.md` blocking bullet.

- [x] Add real test source path dependencies, one file-only execution step and a bounded text-only artifact.
- [x] Run full `python -m unittest discover -s tests` with the installed PowerShell environment.
- [x] Run `git diff --check`; record exclusions and exact test counts.
- [x] Require independent review before publication for hosted verification.

## Execution record

- Base: `c9eba877c25adc3632be3ae03898b5e046006d22`.
- RED: focused Python suite, three assertion failures for missing safe native runner (2026-11-11).
- RED: compiled managed C# runner failed the actual acknowledgment assertion, "A real write/flush/readback must precede acknowledgment". A prior sandbox file-write restriction and compiler warning were resolved before counting this behavioral RED.
- Scope: implement in the existing development branch using only the listed test and documentation files.
- Ruling: use this requested plan file as the durable execution record, rather than additional workflow bookkeeping files outside the assigned scope.
- RED to GREEN: real held-writer acknowledgment and storage-stage poisoning, malformed-surrogate refusal, cleanup after a missed drain counter, and unavailable native outcome with no published handle. The latter is a managed decision simulation, not a reproduced marshalling/allocation failure.
- RED to GREEN: inspector real method decode, late-call retention after verbose truncation, malformed-JSON unavailable metadata/hash paths, and strict Python parsing of all three metadata reports. Unresolved tokens report unsupported; on-disk bytes do not attest loaded module bytes.
- RED to GREEN: requested recorder injection must have a marker set at the actual fault stage. Native tests separately assert every requested injection was reached; requested scenario and observed injection are separate report fields, and post-launch evidence failure must poison the recorder.
- Ruling: completion-gate marker with a ten-second child fallback replaces a short sleep to reduce timeout-test scheduling races. It is test fixture orchestration only, not production admission IPC.
- GREEN: four focused Python tests; full suite 317 tests with 6 skips; both harness and fixed child C#5/x64/net48-reference compilation with warnings-as-errors; diff whitespace check.
- Pre-publication status: native Windows tests were implemented but not executed locally. Actual native FALSE, timeout/exit259, serviced Framework IL and retained child behavior still required hosted observation; the later results are recorded below.
- Pre-publication review approved the final 12-file diff for exact-SHA hosted CI after focused/full-suite/net48 checks passed. Windows observations were then pending; that review was not runtime acceptance.
- This experiment changed no production source, privilege boundary, production script, build/package input or runtime callback. It ran no VBox/system effect or primary-Windows test and did not merge or release a build.

## Hosted execution result

- Exact published test-only commit: `f9bff11790b5f8324218a4c3d67be171b8526627`. Native push run [43027196442](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43027196442) and PR run [43027208962](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43027208962) passed on attempt 1. All 11 naturally triggered exact-commit runs passed on attempt 1, with no failure, cancellation, rerun or manual dispatch; the [execution record](../EXECUTION-2026-11-11-native-launch-observation.md) lists every run.
- Independent final artifact review accepted 16 distinct attempts (17 snapshots), one observed native FALSE/error 2 and ten created children. Each child's original handle reached native signal, exit-code query and close; timeout and injected uncertainty stayed UNKNOWN. Controlled WAIT_FAILED was drained separately, not a persistent real wait failure. All requested injection sites were reached.
- The 232 total checks include 64 managed checks and 168 further native-case checks. The unavailable native-return case remains a managed simulation. All observations deny mutation authority.
- Actual loaded StartWithCreateProcess raw IL and exception regions established redirected stream construction after native success and before process association, without local exception protection. Verbose-output truncation did not truncate the raw IL or call scan. This is private-method evidence, not full runtime-chain attestation or OOM reproduction.
- Artifact digest, exact-commit association, loaded-module identity, disk-hash caveat, host identity and review limits are in the [execution record](../EXECUTION-2026-11-11-native-launch-observation.md). Runtime source/scripts remain unchanged at `175e6a4`; launch/capture/wait repair, native two-pipe capture and general system retry remain future work.
