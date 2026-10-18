# Portable-VirtualBox modernization plan

Status: planning / baseline, 2026-10-18.
Target repository: `zlocorp/Portable-VirtualBox`.
Historical fork preserved: `archive/legacy-zlocorp-2020` at `6b91c6d3f664535ab31a9038ada1db11c83bf5cc`.
Clean upstream snapshot: `work/upstream-baseline-2026` at `5b58dbbe701c3e2eb348942a9059708063b0cb96`.
Development branch: `dev/modernization-2026` (initially from that upstream snapshot).

## Scope and decisions

- Start from `vboxme/Portable-VirtualBox:master` as of the recorded snapshot. Do not merge or cherry-pick the historical `zlocorp` branch.
- Do not import any third-party fork as a whole. `Deac2`, `bitamind`, and others can be consulted for ideas, with each adopted change explicitly reviewed for compatibility, safety and license.
- Prefer incremental modernization of the AutoIt launcher until a different implementation is justified by tests or technical constraints.
- Do not change the repository default `master` branch, publish a release, or execute a destructive migration while working on this development branch.
- Preserve upstream author notices and license terms. Licensing and distribution of VirtualBox and optional Extension Packs must be reviewed separately.
- Initial priority: Windows 11 x64 and a currently supported Oracle VirtualBox 7.2.x release, to be verified at implementation time. Older versions and x86 hosts are not implicitly supported.
- 'Portable' means relocatable application files and VM data, *not* zero system changes: modern VirtualBox uses drivers and services on Windows and may require elevation.

## Baseline observations (source inspection, not runtime proof)

In upstream `source/Portable-VirtualBox.au3`:
- Line 28: `#RequireAdmin` elevates the entire launcher.
- Around lines 678-720, 864-964: COM and driver/service registration, stop and deletion paths.
- Around lines 818-837: repeated `cmd /c set VBOX_USER_HOME=... & ...` command construction with path/quoting risks.
- Around line 963: process termination by a shared executable name.
- Around line 1798: `taskkill /im msiexec.exe /f` can terminate unrelated Windows Installer processes.
- Around lines 96-99: default Oracle download URLs are fixed to VirtualBox 7.0.20 and currently use HTTP.
- `build.bat` uses bundled AutoIt/7-Zip executables and does not reliably fail when compilers fail, nor has an automated verification gate.
- No included automated test framework is present in the upstream tree.

Treat these as **review targets**, not assumptions that every operation fails in every environment. The line numbers refer to upstream snapshot `5b58dbbe`.

## Safety invariants

1. Never remove, stop or replace a pre-existing Windows service, driver, DLL or process merely because its name matches VirtualBox. Track and verify ownership of resources created during the current run.
2. No unscoped `taskkill /im msiexec.exe /f`, process termination by name, or deletion from Windows system directories.
3. Treat any installed Oracle VirtualBox and existing active VMs as external resources. Preflight checks must refuse unsafe coexistence or switch to a deliberately supported mode.
4. Normal failures, crashes and cancellation should not remove or corrupt VM data. No direct rewriting of user VM XML without explicit migration, backup and rollback.
5. All paths, especially `VBOX_USER_HOME`, must be normalized and tested with spaces, non-ASCII characters, drive-letter changes, and removable media.
6. Track each privileged operation, its success/failure, and reversible cleanup action. Fail closed when a privileged command fails instead of continuing blindly.
7. Downloads must use HTTPS, validate release identity and integrity, and never automatically run unverified downloads. Do not silently install optional Oracle Extension Packs.
8. Do not assume x64 compiled AutoIt means support for a particular Windows/VirtualBox version. Use a documented compatibility matrix and runtime checks.
9. Any cleanup or repair operation must explain potential changes before execution and provide logs sufficient to audit what happened.
10. Never run new launcher builds against the only copy of a valuable VM; test against independent disposable VM data.

## Work packages / acceptance

### M0: repeatable baseline build and inventory

- Record source SHA, build tools, versions and checksums (especially bundled executables); decide whether bundled binaries should be replaced by pinned official releases.
- Produce a reproducible Windows x64 build from the original source. Verify the expected output file and nonzero exit codes.
- Add static checks and a smoke test harness that can run without administrator rights or installing VBox drivers.
- Document baseline behavior and the untested areas. No runtime modifications in this package.

Acceptance: exact input/toolchain versions, build transcript, compile result, artifacts/checksums, explicit pass/fail/untested list.

### M1: privileged-operation and lifecycle hardening

- Introduce a separate preflight phase to detect existing VirtualBox processes, services, drivers, hypervisor conflicts and OS constraints.
- Centralize process execution, service state inspection and logging.
- Ensure successful resource creation is recorded before cleanup is attempted; preserve external resources.
- Replace name-only process termination and unscoped `msiexec` termination with tracked process/operation handling.
- Decouple harmless GUI/settings actions from unnecessary administrator elevation where feasible.

Acceptance: mock/service-owner tests for pre-existing resources, partial failure, cancellation, restart, and cleanup. Real Windows validation in an isolated test machine only.

### M2: profile and VM data safety

- Define a canonical portable data layout and `VBOX_USER_HOME` policy, support relocation and path changes.
- Prefer supported VBoxManage/configuration operations to ad hoc VirtualBox XML string replacement.
- Prevent silent overwrites or implicit migration of existing VM registries, disks and snapshots.
- Test paths containing spaces and Cyrillic characters, and startup from a changed removable-drive letter.

Acceptance: disposable VM tests pass and external/user data remain unchanged.

### M3: VirtualBox 7.2 compatibility

- Select and verify an Oracle VirtualBox release; verify official download URL, signature, checksum and package/extraction layout.
- Check COM, VBoxSDS, VBoxSVC, VBoxSUP, VBoxNetAdp, USB and network behavior for that version.
- Make optional components opt-in; do not bundle Oracle payloads without checking redistribution terms.
- Cover first run, successive run, graceful shutdown, forced failure and coexistence scenarios.

Acceptance: Windows 11 x64 end-to-end tests with real VirtualBox on an isolated disposable environment and logs.

### M4: product experience

- Add consistent diagnostics, understandable errors, Russian/English UI review, configurable settings and update discovery.
- Preserve other original languages until they can be tested or explicitly retired.
- Update interface and branding only after stable system behavior.

Acceptance: smoke tests of setup/launch/exit and locale coverage; no data loss.

### M5: release automation

- CI with pinned audited toolchain, static tests and Windows build.
- Release ZIP first; optional SFX and signing after safe packaging is demonstrated.
- Checksums, provenance, changelog, license notices and documented upgrade/rollback.
- Publication and default-branch merge are explicit release gates, not automatic effects of development.

Acceptance: clean checkout builds, CI passes, artifacts are reproducible/auditable, manual Windows test evidence is recorded.

## Execution policy

- One focused change set/PR per work package or smaller coherent fix; do not combine core lifecycle rewrites with UI/translation changes.
- Each code change carries a regression test or documented proof when automated execution is unavailable.
- Prioritize evidence from current upstream code and Oracle documentation over stale fork README claims.
- Do not describe compilation, Windows driver testing or end-to-end compatibility as 'passed' without actual evidence.
