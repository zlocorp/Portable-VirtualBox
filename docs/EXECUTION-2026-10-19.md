# Execution report: package preparation and native lifecycle policy

Report date: 2026-10-19. Evidence timestamps below are 2026-10-18 UTC. Status: **development preview, VM startup still disabled**.

This report supersedes the earlier report's unresolved wrapper extraction and 13-test baseline. It does not replace that report's historical evidence or claim complete modernization.

## Code and repository boundaries

- Development: `dev/modernization-2026`, draft [PR #7](https://github.com/zlocorp/Portable-VirtualBox/pull/7), targeting `work/upstream-baseline-2026`.
- Verified executable-code head: `d83e6ffcf35f4c583b712d9729c8de21ffe9159f`.
- Verified tree: `11a5ed036d8bdfb38b56d4713176cc6d47545928`.
- PR CI checkout: GitHub-generated merge commit `0bfdfd3264dc89c8cbcc714bd108b1881bb80d75`. Its tree matches that executable-code head exactly; this is not a merge into master.
- Historical master and archive remain `6b91c6d3f664535ab31a9038ada1db11c83bf5cc`; clean upstream reference remains `5b58dbbe701c3e2eb348942a9059708063b0cb96`.
- No user PC, driver install, Oracle MSI installation, real VM, release publication or master merge was used.

## Verified results

| Check | Evidence | Result |
| --- | --- | --- |
| Python regression suite | [Core CI 39170915594](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39170915594), Windows package job, local rerun | 35 tests pass |
| Native AutoIt policy | [Native CI 39170915558](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39170915558), job 117803576660 | 56 journal assertions + 11 runtime assertions, zero failed |
| Windows x64 build | Core CI, job 117803604475 | Compile, compiled selftest, read-only diagnostics, fail-closed Server preflight and Cyrillic/space path build pass |
| Actual Oracle package | [Preparation CI 39170915618](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39170915618) | Pinned wrapper downloaded, signature/hash verified, MSI/CAB passively extracted, read-only x64 MSI identity verified |
| Source audit | Core CI | Active-entrypoint enforce gate passes; archived inherited runtime inventoried separately |

The pattern audit reported zero active-entrypoint matches and 57 legacy-reference matches locally. That is a bounded pattern check, not a whole-program security proof. Successful compilation is repeatable, not proven bit-for-bit reproducible. Native policy assertions are not actual driver/service lifecycle tests.

## Real extraction and metadata evidence

Pinned input: `VirtualBox-7.2.20-175154-Win.exe`.
SHA-256: `a81777d2b36380ce042a29e9c554cf032eb46a793f62e3cc82e7411e535c2c26`.
Authenticode: Valid, Oracle America, Inc.

| Extracted file | Architecture | Bytes |
| --- | --- | ---: |
| VirtualBox-7.2.20-r175154-MultiArch_amd64.msi | amd64 | 58,900,480 |
| VirtualBox-7.2.20-r175154-MultiArch_arm64.msi | arm64 | 56,573,952 |
| common.cab | all | 62,090,752 |

The x64 MSI identifies itself as `Oracle VirtualBox 7.2.20`, product version `7.2.20`, manufacturer `Oracle and/or its affiliates`, template starting `x64;`.
The inspection report records `installerExecuted=false`, `msiInstalled=false`, `msiDatabaseUnchanged=true`, `vboxServiceRegistryUnchanged=true`, and `databaseOpenMode=read-only`.

The [committed metadata](evidence/oracle-inspection-d83e6ff.json) was read back from artifact 12152880593, downloaded and checked against its GitHub ZIP digest `7df199e521293438d68d7839d262abe07aacf94ac22a1bbec11efaae54486866`. No Oracle binary payload is committed or redistributed as an artifact. Registry comparison covers VBox service keys/properties, not every system change or running-service status.

Root cause of the earlier parser failure: Oracle VBoxStubBld writes package resources with LANGID 0x0409 (en-US), while the initial parser accepted only neutral resources. Tests first reproduced rejection, then passed with coherent en-US/neutral handling. Mixed/conflicting language resources remain rejected. Source reference: [Oracle VBoxStubBld.cpp](https://github.com/VirtualBox/virtualbox/blob/main/src/VBox/Installer/win/StubBld/VBoxStubBld.cpp), inspected blob `75586ccca0d40c0cd8145e3031e32e6037175bde`.

A subsequent OpenDatabase reflection call failed with DISP_E_TYPEMISMATCH. Boundary diagnostics isolated that call; using the PowerShell COM adapter with explicit string path and read-only integer mode fixed it. The final report includes unchanged MSI hashes before/after metadata reading.

## Implemented runtime foundation

`LifecycleJournal.au3` now models acquisition and reverse cleanup order. Only a confirmed newly acquired resource may become owned. Unknown outcome, pending operation, identity change or foreign session blocks cleanup. Known failed operations do not become successful merely because the flow continued.

Snapshot writes use exclusive creation and flushing, refuse overwrites and preserve partial evidence. Loaded snapshots are diagnostic READONLY state, not cleanup permission. A caller-provided private non-reparse parent directory and authoritative OS observations are still required; these primitives alone are not a crash-safe privileged runtime.

Process ownership no longer relies only on matching PIDs: the pure policy requires matching creation/executable identities and retained-handle evidence from a future adapter. Native tests exercise actual compiled code with synthetic resources and private temporary journal files, not live services.

The old launcher source was preserved byte-for-byte in `source/legacy/Portable-VirtualBox.au3.disabled` using blob `44a4e7b102cdb197ebea0c3d23dd827a57e1ac82`. The new executable entrypoint no longer compiles the old installer/updater/driver mutation code. Ordinary VM startup remains intentionally unavailable.

## Regression history and review scope

- Resumed existing work at `41f9ce0`; baseline 32 Python tests.
- Resource-language fix `95e4599`; 34 Python tests and real MSI/CAB extraction established.
- Native interface checkpoint `4a95a9`: [run 39169466443](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39169466443) compiled and failed 19 of 47 assertions before lifecycle implementation.
- Implementation/quarantine `4909292`: native and core CI passed.
- Final code `d83e6ff`: 35 Python tests, 67 native assertions and all three workflows passed.

Review performed: author-side source/diff review, focused regression tests, native Windows execution, and artifact readback. No independent reviewer or complete security audit is claimed. Later documentation-only commits do not change the verified code.

## Still not implemented

Extraction currently ends at MSI/CAB files. There is no prepared app64 file tree, service/process OS adapter, privileged transaction coordinator, working VM launch/stop, migration, USB/networking acceptance, or release. The next packages are in the [updated implementation plan](plans/2026-10-18-preparation-and-lifecycle.md). The user's physical PC is not the blocker for the next preparation and adapter development work; real Windows 11/driver/VM acceptance remains a separate later gate.
