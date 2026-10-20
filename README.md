# Portable-VirtualBox (modernization branch)

> **Development preview, not a functional portable hypervisor.** VM startup, driver installation and service cleanup remain disabled. Do not distribute this executable as a usable VirtualBox release.

Based on the original `vboxme/Portable-VirtualBox` master snapshot `5b58dbbe701c3e2eb348942a9059708063b0cb96`. Historical personal modifications are not merged; the old fork remains in `archive/legacy-zlocorp-2020`. Work is isolated in `dev/modernization-2026`; draft [PR #7](https://github.com/zlocorp/Portable-VirtualBox/pull/7) targets the clean upstream reference, not historical master.

## Verified development capabilities

- Windows x64 compilation with the official signed AutoIt 3.3.18.0 compiler, including checkout paths with spaces and Cyrillic characters.
- **Native read-only Windows observations:** SCM service configuration/status, process identity through retained query handles, installation keys in both registry views, and workstation/server product type. Unknown/denied observations block preflight instead of becoming false absence. Querying a resource never grants ownership or permission to mutate it.
- Exact-version Oracle download verification and passive PE resource extraction into MSI/CAB files.
- **MSI/CAB to new app64 file preparation:** the pinned Oracle 7.2.20 package produces 185 application files / 247738522 bytes without running its installer, MSI actions or any payload. Read-only MSI tables determine placement; cabinet callbacks use Unicode-aware file I/O. Per-file hashes, key AMD64 headers, signatures and unchanged inputs are checked in CI.
- **Journaled lifecycle coordination:** persist intent, recheck identity, validate acquisition receipts, confirm results and clean up in reverse order. Cancellation, partial failures, storage failures and changed resources are tested with synthetic effects. Real exclusive UTF-8 snapshots are used in native tests. This is not a completed privileged service/process effect adapter and is not wired into the preview launcher.
- Read-only VM registry inventory and regression tests for malformed input, download races, staging publication, XML encodings and Windows paths.

The old runtime is preserved byte-for-byte as `source/legacy/Portable-VirtualBox.au3.disabled` and is not compiled. The preview does not request administrator rights or start virtual machines. Hosted test results do not establish coverage under a standard-user Windows account.

## Commands

```text
Portable-VirtualBox_x64.exe --version
Portable-VirtualBox_x64.exe --selftest
Portable-VirtualBox_x64.exe --diagnose
Portable-VirtualBox_x64.exe --preflight
```

Diagnostics print status/counts without private image paths or service account names. An unknown observation returns diagnostic exit 4. A blocked preflight returns 3. A clear preflight is neither ownership evidence nor authorization to run an unverified runtime. With no arguments the preview shows a warning and exits.

Developer tools:

```powershell
./scripts/build.ps1 -AutoItRoot 'C:\Program Files (x86)\AutoIt3'
./scripts/test-native.ps1 -AutoItRoot 'C:\Program Files (x86)\AutoIt3'
python -X utf8 -m unittest discover -s tests -v
python scripts/audit_source.py --enforce
python scripts/oracle_release.py 7.2.20
python scripts/vm_inventory.py 'C:\Portable-VirtualBox\data\.VirtualBox\VirtualBox.xml'
```

`python scripts/prepare_app64.py --help` describes the Windows developer preparation interface. It requires a trusted expected wrapper checksum and publisher-signature validation by its caller; the hosted workflow performs those checks. The output directory must not already exist. This tool prepares files, not system prerequisites, COM registration or drivers, and is not yet integrated into the AutoIt UI.

VM inventory hides UUIDs and paths unless `--details` is requested. It does not migrate data.

## Functional CLI and portable configuration smoke (2026-10-20)

Disposable Windows Server 2022 CI now confirms that the prepared Oracle VirtualBox 7.2.20 app64 can execute `VBoxManage --version`, `list vms`, and `list systemproperties` without installing Oracle. A second test set `VBOX_USER_HOME` and `machinefolder` to separate private directories, then created/registered a test VM with a `.vbox` file stored in that portable directory. **No guest VM was started.**

A controlled separate MSI reference installation with only `VBoxApplication` installed both `VBoxSDS` and `VBoxSup`. Importantly, the uninstalled portable CLI **automatically registered `VBoxSDS`** with a persistent service path pointing to its temporary app64 location. This is an unresolved portability/safety issue, not a release-ready feature.

- [CLI smoke with detected side effect](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39399187350)
- [Successful official MSI reference comparison](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39399299608)
- [Successful portable configuration fixture](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39400449110)
- [Evidence and follow-up plan](docs/EXECUTION-2026-10-20-runtime-smoke.md)

## Two real blank-VM sessions on one disposable Windows host (2026-10-20)

[GitHub Actions run 39416531988](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39416531988) proved a complete **clean-host two-cycle** with the prepared Oracle 7.2.20 app64 and separately installed signed VBoxSup. First boot/poweroff, VBoxSDS unregistration, VBoxSup stop/driver-store removal, and guarded deletion of the leftover stopped VBoxSup service were verified; the runner was left with zero VBox services and no published INF or system driver file. The same original VM configuration and UUID were reused for a second headless start/poweroff, followed by the same verified cleanup. **No guest OS or disk was booted.** The process remains an isolated research workflow, not an implemented production launcher; installed-VBox coexistence and drive-letter relocation still need testing.

[Full two-cycle evidence](docs/EXECUTION-2026-10-20-two-cycle.md).

## Status and evidence

See the [latest coordinator report](docs/EXECUTION-2026-10-20-coordinator.md), [completed coordinator plan](docs/plans/2026-10-20-lifecycle-coordinator.md), [Windows observation report](docs/EXECUTION-2026-10-19-observation.md), [app64 preparation report](docs/EXECUTION-2026-10-19-app64.md), [broader roadmap](docs/MODERNIZATION-2026.md), and [security model](docs/SECURITY-MODEL.md).

At the latest verified executable-code checkpoint `503b435`, the Python suite contains **89 tests**: Windows passes 88 and skips one symbolic-link test; Linux passes 84 and skips five Windows-native tests. The native suite passes **351 assertions across 9 compiled harnesses**, including 187 new coordinator/storage/callback/token assertions. Core x64 build and the actual Oracle/app64 preparation also pass. None of this establishes Windows 11 driver/VM compatibility or bit-for-bit reproducible AutoIt binaries.

## Attribution and release boundaries

Preserve the original launcher credit to Michael Meyer and contributors and the original license in `LICENSE.md`. This branch does not silently relicense upstream. Deac2 and bitamind were research references, not wholesale imported code. Oracle payloads and Extension Packs are not published as CI artifacts or project releases. Existing upstream BUILDING.md describes historical packaging and is not the current CI procedure.

Next work prioritizes portable VM configuration relocation, guarded startup/shutdown orchestration and Windows 11/installed-VirtualBox coexistence. Clean-host empty-VM boot, two restarts and complete driver cleanup were verified in disposable CI; production safety is still unproven. The coordinator's synthetic receipts do not authorize actual system mutations. Neither a master merge nor a release has been performed.
