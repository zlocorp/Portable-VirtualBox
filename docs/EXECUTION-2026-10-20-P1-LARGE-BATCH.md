# Large product batch A: native profile preparation, CI service path, diagnostic ZIP

Date: 2026-10-20. This execution report describes a **development-only preview**. It is not a functional, redistributable portable VirtualBox hypervisor.

## Source and branch contract

Base remains the pristine original `vboxme/Portable-VirtualBox` commit `5b58dbbe701c3e2eb348942a9059708063b0cb96` on `work/upstream-baseline-2026`. All work is committed to `dev/modernization-2026` with [Draft PR #7](https://github.com/zlocorp/Portable-VirtualBox/pull/7). Old `master` and `archive/legacy-zlocorp-2020` remain at `6b91c6d3f664535ab31a9038ada1db11c83bf5cc`. There is no merge, release, user-machine execution or Oracle binary redistribution.

Verified executable-code/test/CI checkpoint: `2c4679648cec499f65aeaace314b2b7e5a755742`. Following README, roadmap and report edits are documentation only.

## Feature 1: real first-run portable profile in the compiled AutoIt EXE

`source/PortableProfile.au3` now provides:
- `_PP_Inspect(root)`: pure read-only existing-directory/attribute checks.
- `_PP_Ensure(root)`: creates only `data/.VirtualBox`, `data/Machines` and `logs` inside an existing, permitted absolute drive path.
- Rejects UNC, traversal, reserved DOS components, control characters, unrelated existing files, unsafe/reparse-point ancestor directories and collisions. Does not overwrite any user files, create/delete VirtualBox binaries, rewrite XML or manipulate Windows registry.
- If a folder creation fails, reports a block without removing previously created user data; partial empty folders may remain after an exceptional failure.

The production-visible CLI adds `--profile-status` (0 READY, 2 MISSING, 3 BLOCKED) and `--prepare-profile` (0 success, 3 blocked). The RU/EN diagnostic GUI gains a working **Prepare portable folders** button and displays the destination path, status and missing Oracle payload warning.

Native TDD: [red run 39436102136](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39436102136) showed ten failed assertions of 25 against the interface stub. [Green run 39436399066](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39436399066) passed all 25. Windows compiled-EXE acceptance at [run 39439373623](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39439373623) showed actual initialization, repeat with preserved sentinel bytes and refusal to overwrite a preexisting foreign `data` file, with no partial `logs` creation. Separate Cyrillic-path build and normal diagnostics still pass.

## Feature 2: real, compiled AutoIt to Oracle system service proof (CI only)

`source/PortableCISession.au3` is a clearly marked **non-shipping experimental code path**. Hidden `--ci-service-smoke` is not in the regular help or GUI; it refuses execution outside an expected GitHub-hosted Windows runner with an application root under RUNNER_TEMP. Environment markers are a safeguard against accidental execution, not a security boundary against deliberate spoofing.

On an isolated hosted Windows Server 2022 runner:
1. Prepare authenticated Oracle 7.2.20 app64 (185 files), then compile native AutoIt using signed official 3.3.18.0 compiler and place launcher beside `app64`.
2. Compiled launcher creates `data/.VirtualBox` and `data/Machines`.
3. The compiled launcher verifies no existing VBox installation, services or known processes; runs `VBoxManage setproperty machinefolder` from its own app64 under its private VBOX_USER_HOME.
4. Oracle auto-registers VBoxSDS. Native read-only SCM probe checks exact image path, service kind/start type and LocalSystem identity.
5. After bound waiting for all known VBox processes to exit and VBoxSDS to stop, the compiled launcher revalidates the same identity, invokes Oracle `VBoxSDS.exe --unregservice` and confirms VBox services and processes are absent.
6. `VirtualBox.xml` exists under the portable private profile, not under the normal Windows user profile.

Initial test [run 39438152796](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39438152796) reached verified `CI native session: CLEAN` but intentionally failed because `VBoxManage list vms` did not create the required new profile XML. Replacing the step with `setproperty machinefolder` addressed the cause. [Green native real-system run 39438429411](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39438429411) confirms `CI native session: CLEAN`, zero orphan VBox registrations/processes and a persisted private VirtualBox.xml. Native pure-policy tests first failed 3 of 14 on stubs [run 39437597987](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39437597987), then passed.

This experiment **does NOT** install/start VBoxSup, launch Oracle VirtualBox Manager GUI, boot a guest VM or provide a safe Windows 11 user-machine startup/cleanup API. Prior system driver/empty-VM experiments remain isolated PowerShell research tests, not yet wired into the regular GUI. No regular-use Start button has been enabled.

## Feature 3: testable minimal diagnostic ZIP (not a VM release)

`scripts/package_preview.py` creates exactly four ZIP entries:
- `Portable-VirtualBox.exe` (compiled unsigned AutoIt development executable)
- `LICENSE.md` (original license retained)
- `README.md`
- `PREVIEW-NOT-A-HYPERVISOR.txt` (clear functionality and safety notice)

The zip and its separately generated SHA-256 sidecar are created without overwriting existing outputs; no Oracle EXEs, drivers, MSI/CAB, old 7za/DevCon/SnetCfg or user VM data are present. CI verifies ZIP member allowlist, hash and **executes the ZIP-extracted EXE** in a second Cyrillic directory. This reproduces first-run profile creation from the actual distributed file bytes.

Evidence: [Core CI 39439373623](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39439373623), artifact `portable-virtualbox-diagnostic-preview`, ID `12272514060`.

Verified inner ZIP SHA-256: `e561574b50e011e9a40892db2a284908df3bbe8a509fb50dbfefd78f466717b2` (CRC and member list independently checked after GitHub artifact download). This is **not** an Oracle product release.

## Complete CI gates at code checkpoint

| Workflow | Result |
| --- | --- |
| [Core 39439373623](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39439373623) | Linux Python **105 tests**, 100 pass / 5 Windows-only skips; compile x64, localized CLI, Unicode build, compiled profile CLI repeat/collision, ZIP allowlist/SHA/unpacked EXE pass |
| [Oracle preparation 39439373630](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39439373630) | Windows Python **105 tests**, 104 pass / 1 symlink privilege skip; signed Oracle wrapper and file-only 185-file app64 pass |
| [Native AutoIt 39439373624](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39439373624) | **12 compiled harnesses, 487 assertions, zero failures**, including profile 25, CI policy 14, localization 97 and previous safety coverage |
| [Compiled real Oracle service 39438429411](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39438429411) | Native executable sets real portable Oracle profile and unregisters its own auto-created VBoxSDS, CI-only |

These are evidence of a **larger coherent first-run/product packaging package**. They do not fulfill all functional launcher or Windows 11 release acceptance requirements.

## Next large package

**Batch B is not yet implemented:** adapt the proven signed VBoxSup kernel driver installation, start, stop and exact-owner cleanup from disposable scripts to reviewed native privileged adapters, with separate elevation, rollback evidence and explicit success/failure/cancellation states. Only then expose **Start/Stop VirtualBox Manager** in normal RU/EN GUI, with real Windows 11 and installed-VBox coexistence tests. Do not let read-only observation or a saved journal grant authority to remove a system service.

The following package handles user-directed signed update discovery/staging and genuine release packaging only after the lifecycle acceptance gate. Keep all inherited executables quarantined and historical branch unchanged.
