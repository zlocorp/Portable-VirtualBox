# Read-only native Windows observation implementation plan

Execution: inline. The user authorized development and hosted CI without their PC. This plan follows the approved modernization roadmap; it does not authorize VM startup, service mutation, a master merge or a release.

**Goal:** replace ambiguous registry/process-name checks with read-only native Windows observations that fail closed on uncertainty.
**Architecture:** query-only AutoIt adapters, retained process handles, bounded service configuration/status reads, explicit PRESENT/ABSENT/EXITED/UNKNOWN results. Observation is not ownership. Preflight consumes observations; startup stays disabled.
**Spec:** docs/SECURITY-MODEL.md and docs/plans/2026-10-18-preparation-and-lifecycle.md.
**Baseline:** `9d5e74a721064ed0c4e726eaf575fc37663baa30`; app64 preparation was already complete.
**Verified code/test head:** `d6f2137ec845ba182524b7f58bdf499a9a63e582`.
**Tools:** AutoIt 3.3.18.0, Windows query APIs, Python, hosted Windows Server 2022/Ubuntu.

## Global constraints

Preserve master, archive and clean upstream reference. No service start/stop/create/delete, production process termination, MSI execution, driver installation or VM mutation. Tests may start private copies of their harness that exit naturally. Access errors and incomplete observations must not be reported as absence. Default output omits paths and account names. A retained query handle supplies identity, not proof of resource acquisition.

## Review focus

PID reuse and exit, error classification, service changes between reads, UTF-16 buffer bounds, 64-bit FILETIME precision, handle lifetime, closed-token reuse and new Windows Server builds misidentified as Windows 11.

## Task 1: specify and reproduce adapter regressions

- [x] Read actual baseline; Python baseline 56 discovered, Linux 51 passed / 5 skips. Existing 67 native assertions continued to pass in the red checkpoint.
- [x] Specify scoped error classification and UNKNOWN/negative preflight states.
- [x] Exercise real self-process identity, close/double-close, naturally exiting child and built-in RpcSs query.
- [x] Compare changed service identity, pending state and mismatched process identity.
- [x] Observe compiled red checkpoint: 53 failures / 77 new assertions in run 39245593510 before implementation.

## Task 2: implement query-only adapters

- [x] SCM access: SC_MANAGER_CONNECT and SERVICE_QUERY_CONFIG/SERVICE_QUERY_STATUS only.
- [x] Process access: PROCESS_QUERY_LIMITED_INFORMATION plus SYNCHRONIZE, retained in process-local non-reused tokens.
- [x] Read PID/creation/image from the same handle; represent FILETIME as exact high/low hex.
- [x] Bound UTF-16 service buffers and close acquired query handles; test invalid handles and repeated open/close cycles.
- [x] Observe Oracle/Sun installation keys in both registry views without equating denied access to absence.
- [x] Determine workstation/server type in addition to build.
- [x] Native suite passes with archived runtime excluded.

## Task 3: fail-closed preflight and diagnostics

- [x] Fix negative/unknown counts and unknown installation states with native regression coverage.
- [x] Query known VBox services through SCM and include headless/network helpers in process checks.
- [x] Use native installation/OS observations in diagnostics; output statuses/counts and nonzero status on uncertainty.
- [x] Preserve the pure preflight helper's old argument form while passing actual product type in the host-facing function.
- [x] Compile and execute diagnostic/selftest/preflight on hosted Windows without enabling VM startup.

## Task 4: final review and evidence

- [x] Full Python suite: 59 discovered; Linux 54 pass / 5 skips, Windows 58 pass / 1 skip.
- [x] Compiled native assertions: 56 lifecycle + 11 runtime + 77 observation + 20 edge checks; zero failed.
- [x] Core x64 build and existing Oracle app64 preparation pass on the verified code checkpoint.
- [x] Review access masks, handle lifetime and uncertainty paths; author-side review only.
- [x] Record report and remaining gates; refresh the existing draft PR without merging.

## Execution ledger and rulings

- Reused completed app64 work instead of repeating it. Isolated local workspace was restored from a commit-bound connector snapshot because direct git networking cannot resolve github.com.
- Service/OS implementation passed first; process-open failures were narrowed using a temporary boundary harness. Actual AutoIt values were integral Double PID and signed -1 for 0xFFFFFFFF. Accept only exact numeric DWORD-range integers, then normalize; do not broaden access rights or accept fractions/strings.
- Static mutation matching now uses identifier boundaries: `_WinObsProcessClose` closes a query handle and is not the built-in `ProcessClose`. Added matcher tests and removed the temporary diagnostic harness.
- OS-facing helper passes actual product type. Default product type on the pure compatibility helper is not a claim that an unknown host is supported.
- Service observations are non-atomic snapshots. A future privileged coordinator must revalidate and prove acquisition separately; no journal cleanup permission is inferred from an observation.

Evidence: [execution report](../EXECUTION-2026-10-19-observation.md). Next bounded package: journal/observation coordination with synthetic effect adapters and injected failure cases, still without real service or VM mutation.
