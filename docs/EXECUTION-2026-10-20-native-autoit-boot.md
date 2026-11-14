# Native AutoIt empty VM boot and exact-owned driver cleanup

Date: 2026-10-20. Branch: `dev/modernization-2026`; Draft PR #7 against clean original `work/upstream-baseline-2026`.

**Scope:** real empty VM boot from the actual compiled `Portable-VirtualBox_x64.exe` on a disposable GitHub-hosted Windows Server 2022 runner; signed VBoxSup provisioning and controlled cleanup are still executed by existing separately tested PowerShell adapters. This is NOT a shipping Start/Stop UI or Windows 11 acceptance.

## Checkpoints

- Native process contract RED: [run 39447981848](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39447981848), six targeted assertions failed with an intentionally nonfunctional process adapter.
- Native process GREEN: [run 39448200650](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39448200650), 12 assertions passed for exact PID, return code 0/17, stderr/stdout, Unicode paths, timeouts and missing files.
- Native boot policy RED: [run 39448605299](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39448605299), five missing-policy/parse assertions failed.
- Native boot policy GREEN: [run 39448936566](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39448936566), 17 assertions passed for strict CI identity, exact running driver service, VM state/UUID parsing and local-host denial.
- The first full runner [39449853635](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39449853635) showed all 8 native VM commands exit 0 but failed on a PowerShell `$HOME` read-only variable in the independent observer. A second [39450070046](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39450070046) also reached native boot success but failed the independent `showvminfo` probe (exit 1). After logging stderr and correcting that verification path, **[run 39450334031](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39450334031) PASSED ALL STEPS**.

## What the compiled AutoIt executable now actually does

The *hidden, explicitly fenced* `--ci-vm-session` mode is allowed only in a private root under `RUNNER_TEMP` with the exact hosted GitHub Actions repository/OS markers. It is not available from the normal user-facing GUI or documented CLI. The markers are a guard against accidental use, **not a security boundary against maliciously forged environments**.

`PortableCIVM.au3` checks existing local profile, exact VBoxSup service configuration and no other VBox installations/processes, then executes via `PortableCommand.au3`:
- `VBoxManage setproperty machinefolder` (private data path)
- `VBoxManage createvm ... --register` for a **fresh named fixture only**
- `modifyvm` with 128 MiB, one CPU, disabled network/boot devices
- `showvminfo --machinereadable`, requiring `poweroff` and a well-formed UUID
- `startvm --type headless`, requiring exit 0
- `showvminfo` requiring **running**, exact same UUID
- `controlvm poweroff`, requiring exit 0
- `showvminfo` requiring **poweroff**, exact same UUID

The command runner uses a retained query-only child-process handle, checks the actual Windows exit status, reads bounded stdout/stderr and enforces individual deadlines. It does not kill processes by name or auto-clean up if an outcome is unknown. On failure after VM start it returns nonzero and the disposable runner must be destroyed; real-user crash recovery is not yet implemented.

An independent Windows PowerShell observer validates the native log, signed Oracle binary, same UUID, `poweroff`, zero VirtualBoxVM processes, isolated profile and expected `VBoxSDS`/`VBoxSup` configurations, then generates an inspectable boot receipt. Only after that receipt does the workflow run its previously proven exact-owned `VBoxSDS` unregistration and `VBoxSup` driver-store/service cleanup.

Verified final CI log:
- `Compiled native AutoIt exit = 0`
- `Native VM machinefolder/createvm/configure/before/start/running/poweroff/after: EXITED/0`
- `Native AutoIt VM receipt verified independently: uuid=619944eb-4a93-414f-9e3d-8131ed6b935f, VMState=poweroff, process_count=0`
- `VBoxSup cleanup: SDS=CLEAN, stop=EXIT_0, PnP=EXIT_0, removed=True`
- `PASS: compiled native AutoIt booted/powered off its own VM, independent receipt and signed exact-owned cleanup completed`

The downloaded GitHub artifact 12277732079 was read back and its ZIP integrity and JSON independently inspected: `native_boot_verified=true`, `independently_verified=true`, `startvm_returned_zero=true`, `poweroff_succeeded=true`, `orphaned_vm_process_count=0`, `cleanup_verified=true`, `driver_package_removed=true`, `final_vbox_services=[]`, `errors=[]`. It contains **metadata/logs only**, not Oracle binaries or VM data.

## Existing regression gates

At the executable-code checkpoint `539a7542787ca24195d6f1921ec9ffe3a1728a20`:
- [Core CI 39450351164](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39450351164): Windows x64 AutoIt compile and read-only CLI pass; Linux 107 Python tests discovered (102 pass, 5 platform skips).
- [Windows Oracle CI 39450348618](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39450348618): 107 Python tests discovered (106 pass, 1 symlink privilege skip), complete 185-file Oracle app64 preparation pass.
- [Native CI 39450348623](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39450348623): 14 compiled AutoIt harnesses, **516 assertions, zero failures**.

## Release blockers

This is major functional progress, **but Batch A is not complete**:
- Driver installation/start/stop/uninstall is currently delegated to CI-only PowerShell, NOT a safely reviewed production privileged helper. A normal Windows user cannot execute `--ci-vm-session` through supported UI.
- The compiled EXE manages a blank **headless VM without any guest OS/disk**, not the Oracle **Manager GUI** yet. GUI Start/Stop remains unavailable; no actual user data is altered in these tests.
- Still requires installed-VBox coexistence policy, Windows 11 standard-user/admin handoff, real guest OS boot and bounded crash/cancel/restart rollback and UI review.
- The CI guard is intentionally a conditional, not a cryptographic authorization boundary. All tests run on disposable clean Windows Server 2022. Do not copy these test-only invocation patterns to a regular PC.
- No old fork code, releases, master merges or user machine usage.

## Next large implementation package

Implement **real manager Start/Stop and privileged helper integration** in the non-test GUI, with explicit elevation consent, independently retained resource ownership, and refusal to mutate an existing VirtualBox installation. First establish clean Windows 11 acceptance in an isolated environment, then permit a prerelease. Preserve the existing working RTL/VM private profile and exact cleanup evidence.
