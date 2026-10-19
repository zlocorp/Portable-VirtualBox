# Read-only native Windows observation implementation plan

Execution: inline. The user authorized continuing development and hosted CI, without the user's PC. This is the next adapter package from the approved modernization roadmap, not permission to enable VM startup or publish a release.

**Goal:** replace ambiguous registry/process-name checks with native, read-only Windows observations that fail closed on uncertainty.

**Architecture:** AutoIt adapters call Windows APIs with query-only access. Process observations keep a handle until explicitly closed; service observations read configuration and status through SCM. Results distinguish PRESENT, ABSENT, EXITED and UNKNOWN. Observing a resource never establishes ownership or permission to mutate it. Preflight consumes these observations, but startup remains disabled.

**Spec:** docs/SECURITY-MODEL.md and the next bounded packages in docs/plans/2026-10-18-preparation-and-lifecycle.md.
**Baseline:** dev/modernization-2026 at 9d5e74a721064ed0c4e726eaf575fc37663baa30. The app64 preparation package is already implemented and must not be repeated.
**Tools:** AutoIt 3.3.18.0, Windows query APIs, Python regression suite, GitHub-hosted Windows Server 2022/Ubuntu.

## Global constraints

- Preserve master, legacy archive and clean upstream reference; no merges or releases.
- No service start/stop/create/delete, process termination, MSI execution, driver installation or VM mutation.
- Only synthetic or test-owned short-lived processes may be started by tests. They exit naturally.
- Do not infer absence from access denied, failed API calls, malformed data or an incomplete enumeration.
- Retained-handle identity does not imply that the application created/owns a process. Future privileged coordination must supply creation evidence separately.
- Keep observations local and omit process image paths/account names from default console evidence.

## Review focus

1. PID reuse or exit during observation: never silently bind to a different process.
2. Access errors or invalid handles: UNKNOWN, not ABSENT.
3. Service configuration changes between reads: UNKNOWN; a read-only snapshot is not atomic authority for later deletion.
4. API structure layout, UTF-16 strings and 64-bit FILETIME precision.
5. Handle leaks, stale tokens, double close and false Windows 11 acceptance on new Server builds.

## Task 1: specify and reproduce adapter regressions

Files: tests/native/test_windows_observation.au3; optional interface-only source/WindowsObservation.au3 checkpoint.

- [ ] Run baseline native/Python checks and record source identity.
- [ ] Test error classification: only service-open error 1060 and installation-key errors 2/3 imply ABSENT; access denied and invalid parameters remain UNKNOWN.
- [ ] Test real self-process observation through a retained query handle, stable creation/image identity, closed-token rejection and double-close safety.
- [ ] Test a naturally exiting child: retained observation becomes EXITED without reopening its PID.
- [ ] Test a nonexistent synthetic service name and an existing built-in service with query-only access.
- [ ] Test observation comparison rejecting changed service identity, pending service state, invalid observations and mismatched process creation identity.
- [ ] Execute on hosted Windows and observe failures before implementing behavior.

## Task 2: implement the query-only adapters

Files: source/WindowsObservation.au3 (or focused service/process helper files when needed).

Interfaces: _WinObsService(name) -> observation map; _WinObsProcessOpen(pid) -> token; _WinObsProcessRead(token) -> observation map; _WinObsProcessClose(token) -> bool; _WinObsInstallation() -> observation map; _WinObsOS() -> observation map; _WinObsFailure(kind, stage, error) -> status.

- [ ] Use SC_MANAGER_CONNECT plus SERVICE_QUERY_CONFIG/SERVICE_QUERY_STATUS only.
- [ ] Use PROCESS_QUERY_LIMITED_INFORMATION plus SYNCHRONIZE only; retain handles in a token registry, not a caller-supplied PID comparison.
- [ ] Obtain process creation time and image from the same handle; use wait status to distinguish exit. Represent FILETIME exactly, not as a floating-point timestamp.
- [ ] Parse and bounds-check query buffers; close all owned handles on failure.
- [ ] Read both registry views for Oracle/Sun installation keys; distinguish key absence from access failure.
- [ ] Determine workstation/server product type in addition to OS build.
- [ ] Pass native regression suite without enabling legacy runtime.

## Task 3: integrate fail-closed preflight and diagnostic output

Files: source/HostPreflight.au3, source/Portable-VirtualBox.au3, existing/native tests.

- [ ] Add regression cases for UNKNOWN/negative counts and Server product type before fixing the current preflight policy.
- [ ] Query known VBox services through SCM; enumerate relevant VBox processes, including headless helpers, and fail closed on read errors.
- [ ] Use adapters for installation/OS observations and read-only diagnostics, with no sensitive paths in default output.
- [ ] Keep old public preflight helper compatibility where useful, but do not silently accept unknown state.
- [ ] Verify compiled diagnostic commands and preflight on hosted Windows; no VM startup is expected.

## Task 4: final review and evidence

- [ ] Run full Python suite on Linux/Windows, all compiled native tests, core build and existing Oracle preparation on final code.
- [ ] Review API access masks, handle lifetime and every uncertainty path. Record that author-side review is not independent security review.
- [ ] Update report, task checkboxes and Draft PR #7 with actual counts and run links.
- [ ] Record remaining privileged coordinator/runtime work, without claiming Windows 11 VM acceptance.

## Execution ledger

- Planning: branch already includes completed app64 preparation; resume at Windows observations.
- Transport: direct git clone cannot resolve github.com in this container. Use a commit-bound connector source snapshot and local isolated workspace, publish through the GitHub connector with a checked parent/ref.
- Pre-flight interface: adapter observations feed preflight only; they do not restore cleanup authority in LifecycleJournal. Keep that boundary explicit.
