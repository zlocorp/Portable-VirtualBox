# Integrated Manager session: real GUI acceptance

Date: 2026-10-21. Branch: `dev/modernization-2026`.
Implementation started at `1ad6a805`; verified fixed code is [`b4f3841837b5a6e64f148ceb98c397da1bd1d39a`](https://github.com/zlocorp/Portable-VirtualBox/commit/b4f3841837b5a6e64f148ceb98c397da1bd1d39a).

## Actual functionality

The adapted Manager/guest flow from ThatAdminGuy (`a035d06b12`) and skyshay001 (upstream PR #90) is now connected to actual Start, Finish session and Reopen Manager buttons in a separate compiled frontend. It reuses the existing signed VBoxSup staging/start and exact-owned SDS/SUP teardown scripts. It does not install optional USB/network drivers.

`ManagedProcess.au3` uses `CreateProcessW` with explicit executable/CWD/private environment and retains its returned handle. A close is a `WM_CLOSE` request to a window belonging to that process, never a name-based kill. The GUI remains responsive while the worker and VM processes run. Manager exit is not treated as VM exit. A second controller refuses a conflicting session. Cleanup requires original acquisition evidence, the same live controller generation and fresh absence of all VBox activity.

A Manager-only cycle uses a distinct `Session` quiescence proof. The old `Boot` proof remains supported for the headless boot experiment. The Manager adapter never invents `startvm_returned_zero` or guest poweroff evidence.

## Failure found and addressed

Initial real GUI runs reached Manager close, guest preservation and Manager reopen, then failed when immediately closing the newly visible window. They retained the driver rather than guessing cleanup. Failure artifacts from [39565422872](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39565422872) and [39566266793](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39566266793) were downloaded and inspected, including actual window images and Oracle logs.

Oracle displayed a modal error saving `GUI/LastWindowPosition`; its log had already entered `aboutToQuit`. The inspected [upstream Manager source](https://github.com/mirror/vbox/blob/master/src/VBox/Frontends/VirtualBox/src/manager/UIVirtualBoxManager.cpp) schedules geometry persistence after move/resize. This supports the early-close/teardown-race diagnosis; it is not a claim of exhaustive analysis of all Oracle GUI failures.

The controller now observes an enabled window and unchanged geometry for 750 ms before declaring it ready, and queues close until that condition holds. This is asynchronous, not a fixed sleep in the test or automatic dismissal of an Oracle error. The **unchanged** real GUI test then passed the full flow. The quiet-window interval is an operational guard, not a security/ownership proof. Unknown process state and unconfirmed close still block cleanup.

## Verified Windows result

[Manager GUI run **39567202279**](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39567202279), code `b4f38418`, **success** on disposable **Windows Server 2022** with Oracle **7.2.22 r175245**:

1. Clicked Start in the compiled frontend and observed the actual Oracle Manager window/process from the prepared app64.
2. Started a second controller; its Start was refused without changing the original Manager.
3. Created a fresh empty VM, started it headless, independently observed `VMState="running"`.
4. Clicked Finish: Manager exited, the VM remained running and VBoxSup remained loaded.
5. Clicked Reopen: a new Manager process opened while the same VM continued. Clicked Finish again without a test-side delay.
6. Explicitly powered off only the test-owned empty VM, waited for background exit, and verified exact-owned SDS/SUP/driver-package cleanup.
7. Started another session, reopened the same VM UUID in powered-off state, finished and verified a second complete cleanup. VM configuration remained present.

Downloaded artifact **12330836019**, SHA-256 **8dfc1c86e91bd476d1ad4bda8cb502c8b2c79debaa9c7eedd5dcccfd054a71dd**, and inspected the reports, not just workflow status. `manager-gui-proof.json` confirms all six booleans: real Manager opened, guest survived Manager close, Manager reopened with guest, second controller refused, two sessions clean and UUID preserved. The fixture UUID was `1e42c7e2-d366-46bc-94f1-f4c930a13fd6`.

Both cleanup receipts have `cleanup_verified=true`, `driver_package_removed=true`, `final_vbox_services=[]`, `errors=[]`, no published INF or driver SYS, and `cleanup_basis="Session"`. Their `vm_powered_off_before_cleanup=false` deliberately records that cleanup is authorized by current quiescence, not a fabricated boot receipt. `guest_os_booted=false`: this was an empty VM engine test, not a guest OS/disk boot.

## Regressions and source verification

- [Core/x64/public CLI/ZIP **39567208851**](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39567208851): success. Ordinary diagnostic packaging remains six files and excludes the experiment/PowerShell worker.
- [Native AutoIt **39567208877**](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39567208877): **20 compiled harnesses**, zero failures. The new retained-handle test has **12 assertions**, including closing one of two same-image GUI children without affecting the other. Session/window policies have **22 assertions**.
- [Oracle package/Windows regressions **39567208694**](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39567208694): success.
- [Existing headless boot/cleanup **39564388801**](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39564388801) passed at `1ad6a805` after the shared cleanup gained its Session parameter set. Later changes only affected the new Manager controller/test diagnostics; that cleanup implementation was unchanged.
- Downloaded commit-bound source artifact **12330421722** from [39567202301](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39567202301), verified commit marker and source ZIP SHA-256 **9d2616e0419465114687ee2b7fc01d53de037d4154ad8b568bfb2009e9fb4a41**, aligned the local worktree to the actual tested files and reran the Linux suite: **128 discovered, 123 passed, five platform skips, zero failures**. Active-tree guard and whitespace checks passed.

## Unfinished boundary, not a production release

The normal packaged launcher is still diagnostic-only. `Portable-VirtualBox-Session-Test.exe` is a separate non-distributed build. Its frontend has no blanket `#RequireAdmin`, but the tested process inherited the elevated CI runner's token. The effect worker explicitly requires that already-elevated host. **No normal-user UAC handoff has been implemented or accepted.** Environment variables are anti-accident guards, not a security boundary.

Windows 11, interactive DPI/accessibility review, crash/reboot/recovery, hostile same-account races, real guest OS/disk use and general existing-installation coexistence remain unverified. Failure may retain resources for inspection because the test host is disposable; that is not a recovery policy suitable for a user PC. No updater or full settings wizard was added in this package.

The next required integration is the narrowly scoped privileged helper and ordinary-user flow, not another diagnostic counter. Original notices stay in source/CREDITS; About and the six-file preview package were not expanded. No master change, PR merge or release.
