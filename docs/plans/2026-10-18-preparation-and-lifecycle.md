# Package preparation and lifecycle hardening implementation plan

Execution: inline, with regression evidence and hosted Linux/Windows CI. User authorized continuing work without the real PC; no master merge, release, driver install or live VM mutation.

## Agreed scope and provenance

Keep AutoIt as the launcher. Prepare verified Oracle packages without executing them, test lifecycle decisions against synthetic resources, and leave actual startup disabled. Do not import another fork wholesale or change licenses.

The original iteration began at `3556db90e438c347e47857da9b1dba3db2164283`. On resuming after an interrupted turn, the branch already contained input/parser changes at `41f9ce0b5a22c3456e6665621e988bfd783cf94a`. Those changes were read and tested, not blindly repeated. A commit-bound source snapshot at `dd9c09224a1fc312fd7f5b8e1fdc46058111a492` enabled local tests when direct network clone was unavailable.

Preserve master and archive at `6b91c6d3f664535ab31a9038ada1db11c83bf5cc`; preserve clean upstream `work/upstream-baseline-2026` at `5b58dbbe701c3e2eb348942a9059708063b0cb96`. The broader roadmap is MODERNIZATION-2026.md. This iteration does not complete all M0-M5 work packages.

## Task 1: input hardening and regression foundation

- [x] Read current branch and run its existing tests unchanged: 32 Python tests at resumed baseline.
- [x] Review existing destination-race, foreign partial-file, official redirect, bounded response and malformed-name cases. Preserve their tested fixes.
- [x] Verify XML encoding/DTD, foreign namespaces, registry scope, Windows special names and path checks.
- [x] Run the complete updated Python suite locally and on hosted Linux/Windows: 35 tests pass.

Most input hardening was already present after the interrupted turn. This resume verified it and added the en-US resource and quarantine regressions; it does not claim authorship of a new red/green cycle for every earlier test.

## Task 2: actual Oracle installer extraction and metadata

- [x] Establish Oracle's resource format from VBoxStubBld source, not guessed command-line switches.
- [x] Reproduce rejection of valid en-US resources, implement coherent en-US/neutral selection, retain failure on mixed or unsupported language resources.
- [x] Test PE32/PE32+ bounds, invalid manifests, filenames, duplicate entries, exact checksums and new-directory extraction.
- [x] Retrieve the pinned Oracle 7.2.20 installer in hosted Windows, check checksum and publisher signature, and passively extract x64 MSI, ARM64 MSI and common.cab.
- [x] Fix the PowerShell COM marshalling boundary at OpenDatabase, then inspect the x64 MSI in read-only mode.
- [x] Verify product/version/platform, unchanged MSI bytes and unchanged VBox service registry entries; keep metadata only.

Acceptance evidence: run [39170915618](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39170915618) and committed inspection JSON. This completes wrapper-to-MSI/CAB extraction, NOT MSI/CAB-to-app64 file staging or an installed runtime.

## Task 3: native lifecycle policy and snapshots

- [x] Specify and reproduce native lifecycle failures before implementation: 47 assertions, 19 failures against interface checkpoints in run 39169466443.
- [x] Implement planned/owned/failed/releasing/released/uncertain states, ownership confirmation, reverse cleanup order and checked retry behavior.
- [x] Refuse PID-only ownership, changed identities, foreign sessions, ambiguous outcomes and cleanup after loading a disk snapshot.
- [x] Add exclusive UTF-8 snapshot writes, strict parse bounds and private-directory test fixtures, including Cyrillic paths.
- [x] Execute the real compiled AutoIt policy: 56 lifecycle assertions and 11 runtime policy assertions pass in run [39170915558](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39170915558).

Acceptance is a native policy implementation and file-snapshot primitive. Authoritative Windows resource probes, handle management and a durable privileged operation coordinator are separate, unfinished work.

## Task 4: quarantine, CI and evidence handoff

- [x] Remove inherited runtime from the compiled entrypoint; archive the exact old blob as a .disabled reference.
- [x] Enforce the active-entrypoint audit, retain a separate legacy inventory, set bounded jobs and read-only credential scope, and run native tests on the draft PR.
- [x] Verify final executable-code commit `d83e6ffcf35f4c583b712d9729c8de21ffe9159f` with all three workflows passing.
- [x] Record exact commit/tree/run identities, executed counts, real extracted package metadata and explicit remaining work in EXECUTION-2026-10-19.md.

The existing draft PR #7 remains the review vehicle. Its summary is updated as part of the evidence handoff; it must not be merged automatically.

## Next bounded implementation packages

1. **MSI/CAB to application staging:** inspect File/Component/Directory/Media metadata, validate destination paths, expand payload files without MSI execution, verify required x64 runtime/driver/COM files and preserve original package hashes. Acceptance: an inspected new app64 staging tree on disposable CI, no installer or service effects.
2. **Read-only authoritative Windows adapter:** bind process identity to retained handles, query service configuration/status reliably, distinguish access errors from absence, and connect observations to the native policy. Acceptance: native fixtures plus read-only host probes; no delete/stop calls yet.
3. **Privileged coordinator:** validated operation plans, intent durability, bounded command execution, ownership revalidation and rollback. Test against controlled disposable resources before VirtualBox integration. Keep preview startup off until this gate is proven.
4. **Runtime integration and acceptance:** enable an isolated start/stop path only after the earlier gates; then Windows 11/VBox driver, networking/USB and disposable VM tests. The user's PC is not needed for the first three preparation/development packages.

Do not treat this queue as already implemented. Any new spending, release publication or changes to the protected historical refs require separate authorization.
