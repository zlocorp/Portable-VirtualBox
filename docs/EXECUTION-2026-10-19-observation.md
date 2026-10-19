# Execution report: native read-only Windows observations

Date: 2026-10-19. Status: **query adapters implemented and tested; privileged lifecycle and VM startup remain disabled**.

## Scope and checkpoint

The iteration resumed `dev/modernization-2026` at `9d5e74a721064ed0c4e726eaf575fc37663baa30`. That checkpoint already contained tested MSI/CAB-to-app64 preparation; it was not reimplemented. No historical personal patches or other fork were imported.

Verified code/test head: `d6f2137ec845ba182524b7f58bdf499a9a63e582`, tree `2c99928ceead1160b8712193aab6ea39beaf5e60`.
PR CI checkout: GitHub-generated `bb0c92ce0955e05552ad045618e3d1f6855c9335`; this is a temporary CI merge reference, not a merge into master.
Draft [PR #7](https://github.com/zlocorp/Portable-VirtualBox/pull/7) continues to target `work/upstream-baseline-2026`.

## Implemented

- `WindowsObservation.au3`: structured PRESENT/ABSENT/UNKNOWN observations, scoped Win32 error classification, native OS build/product type, and read-only Oracle/Sun installation-key checks in both registry views.
- `WindowsServiceProbe.au3`: SCM connect plus service query-config/query-status rights only; bounded UTF-16 configuration parsing; two observations compared to detect changed or pending state. Service handles are closed after reading.
- `WindowsProcessProbe.au3`: process-local tokens retain handles opened with QUERY_LIMITED_INFORMATION and SYNCHRONIZE only. PID, creation FILETIME and image path are obtained from the same handle, with wait-state checks before/after reading. Closed tokens are invalidated and never reopened by PID.
- `HostPreflight.au3`: UNKNOWN installation state and negative/invalid process/service counts now block. Windows workstation product type is checked instead of treating every new build as Windows 11. Common VBox headless/network helpers are included in process conflict checks.
- `HostDiagnostics.au3`: default output contains statuses/counts, not process paths or service account names. Unknown observations return diagnostic exit 4; unsupported/conflicting preflight returns 3. Ordinary VM startup remains disabled.

An identity observation is **not ownership**. The observer may query a pre-existing process but cannot conclude that the launcher created it. A future coordinator must separately retain creation evidence and revalidate state before any effect. Service reads are snapshots, not atomic cleanup capabilities. A process image path is not a signature or file-content integrity proof.

## Executed verification

| Check | Result | Evidence |
| --- | --- | --- |
| Full Python suite on Linux | 59 discovered: 54 passed, 5 Windows-specific skips | [Core CI 39247976777](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39247976777), local snapshot rerun |
| Full Python suite on Windows | 59 discovered: 58 passed, 1 symbolic-link privilege skip | [Oracle preparation 39247977026](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39247977026), job 118044482327 |
| Native AutoIt lifecycle | 56 assertions, zero failed | [Native CI 39247976729](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39247976729), job 118044481159 |
| Native runtime policy | 11 assertions, zero failed | Same native job |
| New Windows observation tests | 77 assertions, zero failed | Same native job |
| New native edge tests | 20 assertions, zero failed | Same native job |
| x64 compiler and diagnostic CLI | Successful; compiled selftest/diagnostics/preflight and Cyrillic/space checkout build pass | Core CI, job 118044539876 |
| Existing Oracle/app64 preparation | Successful; 185 application files, 247738522 bytes; independent hashes and signature checks pass | Oracle preparation job 118044482327 |

Native total is **164 assertions**, not 164 separate test executables or independent scenarios. Tests use the actual compiled AutoIt implementation. They query their own process, a private naturally exiting child and the built-in RpcSs service. No service was created, started, stopped or deleted by these tests. Invalid handles were exercised against Windows; access-denied classification was tested through the pure classifier, not an artificially modified DACL. Standard-user-account coverage is not claimed: query-only access and absence of an elevation request do not establish the runner account's privilege level.

The native edge suite includes fractional/string/overflow PID refusal, exact integral-Double PID handling, invalid process/service handles, closed-token rejection, bounded/unaligned/unterminated UTF-16 buffers and a naturally exiting executable under a Cyrillic path with spaces. Twenty-five repeated self-observation open/close cycles left the process handle count unchanged.

The existing preparation workflow rechecked input hashes, the prepared file inventory and VBox service registry snapshot without executing Oracle payloads. This remains file preparation, not a successful VM or driver test.

## Regression and debugging record

1. `a9f0383`: interface-only native checkpoint compiled and failed **53 of 77** new assertions before implementation. [Red run 39245593510](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39245593510).
2. `ecfba69`: service/OS/preflight checks passed, but process acquisition failed. A focused temporary diagnostic showed `@AutoItPID` as Double and the AutoIt `0xFFFFFFFF` literal as signed -1; direct same-handle API reads already worked. [Boundary run 39246590053](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39246590053).
3. `9d957de`: validated exact integral numeric PIDs in decimal DWORD range before conversion. Native checks passed. A source-contract test falsely matched `_WinObsProcessClose` as the built-in `ProcessClose`; identifier-boundary matching fixed the false positive and also catches whitespace before a real call.
4. `d6f2137`: all three PR workflows passed. The temporary diagnostic file was removed; substantive regression tests remain.

## Readback and review

The commit-bound source snapshot was downloaded from artifact 12183838568 in [run 39247967438](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39247967438). Outer ZIP SHA-256 `014bb0b4e2c83dbd1d30fbc3b362ee74ff11cb7436ea295fc5079fcbca7de432`, inner SHA-256, CRC and COMMIT.txt were verified. The full Python suite was rerun locally against that snapshot. Active-entrypoint pattern audit passed with zero matched operations; the bounded adapter test checks the literal DllCall API surface and forbids mutation calls. These checks are not a complete static security proof.

Review was author-side source/diff review plus Windows/Linux executions and source readback, not independent review or a complete security audit. The observed adapters expose no service mutation or process termination operation. Production code starts no process in this package; native test children are copies of their harness and exit naturally.

## Remaining gates and next package

- Add a coordinator binding the existing journal, fresh read-only observations and adapter results. Begin with synthetic effect adapters and injected failure cases; do not wire the archived runtime back in.
- Define explicit ownership/acquisition evidence for service creation and process launch. Query access alone must never become cleanup authority.
- Address durable privileged intents, cancellation, partial effects and changed external state. A clear preflight is not race-free permission to act later.
- Implement reviewed system-changing adapters, dependency/COM/driver handling and VM launch only behind separate acceptance gates.
- Windows 11 x64 with real drivers/VMs, installed-VBox coexistence, USB/networking and migration remain unverified. No release, master merge or use of the user's PC occurred.
