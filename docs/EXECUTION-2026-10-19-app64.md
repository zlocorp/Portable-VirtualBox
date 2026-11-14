# Execution report: verified app64 file preparation

Date: 2026-10-19. Status: **file preparation complete for the pinned package; VM startup remains disabled**.

This completes the MSI/CAB staging package in the previous report. It does not constitute a working portable hypervisor, a Windows driver installation, or release acceptance.

## Commits and boundaries

- Started at `12d0c01ab3b1dd9c4dc6ad0e108efee7c8e51dfe` on `dev/modernization-2026`.
- File preparation implementation and normal CLI verified at `be04da1c2c76af2dd93bcfee66d8780a7de5f31f`.
- Final code/CI checkpoint: `1e388ebf045670cb36c042fcc6c9ac0b41a767b2`, tree `7785b3a0f7dbca9fab1983c51566cd7876a36214`. Later report changes do not alter executable code.
- Draft [PR #7](https://github.com/zlocorp/Portable-VirtualBox/pull/7) targets `work/upstream-baseline-2026`. No master merge, release, user-PC access, VM execution or driver installation.

## Actual application output

The pinned Oracle `VirtualBox-7.2.20-175154-Win.exe`, SHA-256 `a81777d2b36380ce042a29e9c554cf032eb46a793f62e3cc82e7411e535c2c26`, was downloaded and its Oracle Authenticode signature verified before preparation.

The new workflow prepares **185 application files, 247,738,522 bytes**, under a new `app64` directory. A separate `.prepared.json` adds one metadata file. All 185 MSI File rows are covered; none falls outside the application root in this pinned package.

- Embedded `#product.cab`: 107 selected members.
- External `common.cab`: 78 selected members.
- Layout derives from read-only `File`, `Component`, `Directory`, and `Media` MSI tables, including aliases, long filenames and cabinet sequence boundaries.
- Thirteen required executable/DLL/driver PE headers are AMD64. Two required driver metadata files are present and nonempty. Other package payloads, including legitimate x86 helper DLLs, are not incorrectly rejected.
- Prepared `VirtualBox.exe` FileVersion: `7.2.20.175154`; Authenticode: Valid, Oracle publisher.
- PowerShell independently rehashed every staged file, checked its size and exact output count, and compared them with the Python-generated inventory.
- Installer/MSI/CAB input hashes and the inspected VBox service registry keys/properties remained unchanged.
- No installer process, `msiexec`, MSI action, extracted executable or VBox driver was run by the preparation code.

## Implemented components

| File | Responsibility |
| --- | --- |
| `scripts/msi_staging.py` | Pure table/layout validation, source joins, media mapping, size limits and new-directory publication |
| `scripts/windows_payload.py` | Read-only native Windows Installer database/stream access, cabinet API entry points |
| `scripts/cabinet_io.py` | Cabinet.dll FDI callbacks using application-owned Unicode file handles and exclusive output creation |
| `scripts/prepare_app64.py` | Verified wrapper-to-app64 orchestration, required-file validation and per-file SHA-256 inventory |

The preparation interface is developer tooling, not yet integrated into the AutoIt user interface. It requires Python on Windows. A trusted expected wrapper hash and prior publisher-signature verification are caller responsibilities; the CI performs both. It is not a general-purpose arbitrary-MSI installer.

## Failure handling and regression evidence

The planner rejects missing/duplicate table keys, dangling joins, directory cycles, unsafe Windows names, target collisions, duplicate file sequences, unsupported compression and malformed cabinet membership. It excludes system/shortcut destinations rather than mapping them into the host OS.

Files are assembled in a new private tree. Existing `app64` destinations are never updated in place. Publication refuses an existing destination, including one appearing during preparation. Missing bytes, copy failures and validation failures do not publish a complete-looking app64 tree. Input payloads are not deleted.

A native path bug was reproduced before the final fix: SetupIterateCabinetW returned WinError 2 before any cabinet callback for a cabinet under the runner workspace's Unicode staging path. Identical bytes enumerated successfully after copying them to another temporary path. A synthetic LZX cabinet fixture reproduced this without Oracle in [run 39218639082](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39218639082). Small Unicode-path tests on another volume had passed, so the initial simpler hypothesis was insufficient.

The fix does not restrict user paths to ASCII or depend on short-name aliases. Cabinet.dll FDI receives an opaque token; Python callbacks open the actual Unicode source path and exclusively create validated target filenames. Only the selected cabinet can be read. Spanning-cabinet requests, unknown file requests and output-size overruns fail closed. Native executable hints are ignored. The precise internal cause of SetupAPI's path handling was not reverse-engineered and is not claimed.

Reference inspected for FDI ABI/callback rules: Microsoft's `win32metadata`, `generation/WinSDK/RecompiledIdlHeaders/um/fdi.h`, blob `208d92112b24d9884174581f7f7c82c8b408ee0e`.

Temporary tracing code was removed in `be04da1`; the successful final preparation uses the normal CLI, not a diagnostic fallback.

## Verification results

Detailed log-reviewed checkpoint `be04da1`:

| Check | Result | Run |
| --- | --- | --- |
| Python suite on Windows Server 2022 | 56 discovered, 55 passed, 1 skipped, 0 failed | [39220194066](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39220194066) |
| Python suite on Ubuntu | 56 discovered, 51 passed, 5 skipped, 0 failed | [39220194089](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39220194089) |
| Native AutoIt policies | 56 lifecycle + 11 runtime assertions, 0 failed | [39220194063](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39220194063) |
| x64 launcher compilation and safe diagnostic commands | Passed, including spaces/Cyrillic build path | Core CI above |
| Real Oracle wrapper through complete app64 preparation | Passed through the normal CLI | Preparation CI above |

The Windows skip is the symbolic-link fixture whose privileges vary on Windows. It passes on Linux. Linux skips five native Windows cabinet/MSI tests; these pass on Windows. Do not add pass counts across platforms as unique tests.

Final checkpoint `1e388eb` reran all three workflows successfully: [core](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39220819492), [native](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39220819600), [Oracle preparation](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39220819520).

Source review found that the earlier audit-artifact wildcard silently retained no files under the hidden `.reports` directory. The final CI uses an explicit two-file allowlist, nonempty-file checks and missing-evidence failure. `static-audit` artifact 12171646879 is present in the final core run.

## Artifact readback

The normal-CLI preparation artifact 12170898231 from run 39220194066 was downloaded, ZIP CRC-checked and verified against SHA-256 `847efa8318ab43d62e7ca359149c05af943543b26f5ce9ab60061b498069f761`. Its recorded checkout is GitHub PR merge ref `833ee0d4c975c8df60e42f21f72421f1abdcc7d5`, not a merge into master.

All 185 path/size/hash records exactly match the preceding successful preparation run 39219766229. Canonical JSON SHA-256 of the file inventory is `c56185a347583cb7e1994712f0245ff22c15d40b828762bea03aeb22ac609505` (sorted object keys, compact separators, array order preserved).

[Committed evidence summary](evidence/app64-inspection-be04da1-summary.json) retains the checks and provenance. CI artifacts contain metadata, not Oracle redistributable payloads. Matching prepared payloads do not prove bit-for-bit reproducibility of AutoIt compiler output.

## Remaining work and limitations

The prepared folder is complete relative to the pinned MSI File table, not evidence that VirtualBox can run portably without its system dependencies. Conditions, custom actions, COM registration and services are deliberately not evaluated or applied. Extension Packs are not downloaded or installed.

Real service/process OS adapters, privileged coordination, dependency checks, VM launch/stop, migration, USB/network support and isolated Windows 11 runtime acceptance remain separate work packages. Do not re-enable the archived runtime or publish this as a usable release.

The caller must provide private staging directories under a trusted parent. This implementation does not claim to resist an administrator or same-account attacker changing directory topology concurrently. Validation is focused source review, regression tests, hosted native execution and artifact readback, not an independent security audit.

Next package: read-only native service/process identity adapters, with negative tests for access errors, vanished/reused processes and changed resource identity, before any privileged mutation is connected.
