# Portable-VirtualBox (modernization branch)

> **Development preview, not a release-ready portable hypervisor.** Normal GUI/CLI cannot start VMs or install drivers. A hidden disposable-runner-only compiled AutoIt mode now orders signed VBoxSup staging/start, real empty-VM boot/poweroff, independent verification and exact-owned VBoxSDS/VBoxSup cleanup using CI-only PowerShell effect adapters. These adapters are NOT a production privileged helper. Do not distribute this EXE as a usable VirtualBox release.

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
Portable-VirtualBox_x64.exe --profile-status
Portable-VirtualBox_x64.exe --prepare-profile
Portable-VirtualBox_x64.exe --lang ru --help
Portable-VirtualBox_x64.exe --lang ru --diagnose
Portable-VirtualBox_x64.exe --lang en --diagnose
```

Diagnostics print status/counts without private image paths or service account names. An unknown observation returns diagnostic exit 4. A blocked preflight returns 3. A clear preflight is neither ownership evidence nor authorization to run an unverified runtime.

**New localized read-only GUI:** double-clicking the compiled EXE now opens a Windows diagnostics panel, automatically choosing RU on a Russian-language host (otherwise EN), with manual RU/EN switching, **Refresh diagnostics**, **Copy report**, and **Close**. All controls have real effects; the GUI cannot start a VM or mutate system services. Russian CLI help/diagnostics are emitted as UTF-8 and verified by Windows CI. The Oracle VirtualBox Manager has its own separate language setting. Visual GUI layout still needs manual acceptance on isolated Windows 11.

**First-run setup:** With no arguments the localized preview opens a read-only diagnostics GUI with a real "Prepare portable folders" button. The explicit CLI command `--prepare-profile` creates only `data/.VirtualBox`, `data/Machines`, and `logs` alongside the EXE; existing files are never overwritten, and unsafe roots/reparse points/collisions are blocked. `--profile-status` reports READY (exit 0), MISSING (exit 2) or BLOCKED (exit 3). An `app64` with Oracle binaries is NOT automatically downloaded or installed by these commands.

**Developer-only native proof:** a hidden `--ci-service-smoke` is limited to the disposable GitHub-hosted Windows runner configuration; it executes the prepared signed Oracle `VBoxManage setproperty machinefolder`, verifies the exact newly registered `VBoxSDS`, waits for an idle service, then unregisters it using Oracle's supported command. This is **not** a production Start/Stop feature or a security boundary that should be exposed on an ordinary Windows PC. [Proof run](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39438429411).

**Integrated native checkpoint (CI only):** `--ci-integrated-session` is omitted from public help and GUI. The compiled AutoIt executable now **orchestrates** signed driver staging/start, VM boot/poweroff, independent host verification and exact-owned cleanup on a single-use Windows Server 2022 runner. [Successful integrated run](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39494324031) / [execution evidence](docs/EXECUTION-2026-10-20-integrated-native-lifecycle.md). Native regression: 16 harnesses, zero failures. Still not implemented: production privilege-separated helper and UAC, real Manager GUI Start/Stop, Windows 11 standard-user acceptance, coexistence and crash recovery.

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

## Product delivery roadmap and binary audit

- [Practical P0–P5 product roadmap](docs/PRODUCT-PLAN-2026-10-20.md): first-run UI, real Start/Stop with guarded driver lifecycle, RU/EN, updates, ZIP and acceptance. **Next task is implementing a usable safe launcher**, not another generic coordinator.
- [Exact inherited binary audit](docs/DEPENDENCIES-2026-10-20.md): bundled AutoIt **3.3.16.1**, `7za 16.04`, DevCon Windows 7 WDK and SnetCfg Windows Server 2003 DDK. Some were unsigned; none is used by the modern launcher. Signed official AutoIt **3.3.18.0** is already used in CI. We plan to **exclude** stale runtime utilities, not simply replace them with arbitrary binaries.

## Self-contained diagnostic preview ZIP

CI packages `Portable-VirtualBox-diagnostic-preview.zip` with precisely four contents: `Portable-VirtualBox.exe`, `README.md`, `LICENSE.md`, and `PREVIEW-NOT-A-HYPERVISOR.txt`. It also publishes a SHA-256 sidecar. The ZIP deliberately **does not contain** Oracle VirtualBox, its driver files, legacy 7-Zip, DevCon, SnetCfg, or a VM. Unpacking it in a new Unicode directory and executing the built EXE's profile setup are checked in Windows CI. This is a testable *diagnostic-only* preview, NOT a functional hypervisor release.

## Native compiled AutoIt VM boot: new experimental milestone

[Hosted Windows run 39450334031](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39450334031) proves the **compiled launcher executable itself** now created, started, inspected and powered off one freshly created **empty** VM in a private `VBOX_USER_HOME`. Each native command has bounded execution and a real Windows process exit code (not merely a PID). An independent host-side `showvminfo` confirmed the exact same UUID and `poweroff`; `VirtualBoxVM` process count was zero. The existing signed-driver test scripts then removed the new `VBoxSDS` and `VBoxSup` resources, leaving no VBox services or driver package behind. CI artifact contents were read back and validated.

**This path is available only through hidden `--ci-vm-session` experimental mode** with strict disposable GitHub runner checks. It is deliberately not exposed from the normal GUI, needs no real user's VM, does not boot a guest OS, and cannot be called a safe Windows 11 production launcher. Its driver installation/cleanup has NOT yet been integrated into a reviewed elevated frontend/backend pair.

- [Full native execution report](docs/EXECUTION-2026-10-20-native-autoit-boot.md)
- [Native VM workflow](.github/workflows/native-vm-session.yml)

## Status and evidence

See the [latest coordinator report](docs/EXECUTION-2026-10-20-coordinator.md), [completed coordinator plan](docs/plans/2026-10-20-lifecycle-coordinator.md), [Windows observation report](docs/EXECUTION-2026-10-19-observation.md), [app64 preparation report](docs/EXECUTION-2026-10-19-app64.md), [broader roadmap](docs/MODERNIZATION-2026.md), and [security model](docs/SECURITY-MODEL.md).

At executable-code checkpoint `539a754`, **107 Python tests** are discovered (Linux: 102 pass, 5 platform skips; Windows: 106 pass, 1 privilege skip). The native suite passes **516 assertions in 14 compiled AutoIt harnesses**; the complete app64 preparation and x64 build pass. Exact evidence is in [the native VM report](docs/EXECUTION-2026-10-20-native-autoit-boot.md). Inherited privileged startup remains quarantined. Core x64 build and the actual Oracle/app64 preparation also pass. None of this establishes Windows 11 driver/VM compatibility or bit-for-bit reproducible AutoIt binaries.

## Attribution and release boundaries

Preserve the original launcher credit to Michael Meyer and contributors and the original license in `LICENSE.md`. This branch does not silently relicense upstream. Deac2 and bitamind were research references, not wholesale imported code. Oracle payloads and Extension Packs are not published as CI artifacts or project releases. Existing upstream BUILDING.md describes historical packaging and is not the current CI procedure.

Next major package is reviewed per-session **real driver-assisted Start/Stop from the AutoIt GUI**, where privileged actions are isolated and can never touch a pre-existing VirtualBox installation, followed by Windows 11/user/coexistence acceptance. First-run profile creation, localized UI, native CLI VM boot and guarded clean-host driver teardown have been demonstrated; a production hypervisor launcher is not yet enabled. The coordinator's synthetic receipts do not authorize actual system mutations. Neither a master merge nor a release has been performed.
