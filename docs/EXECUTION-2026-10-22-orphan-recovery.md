# Explicit recovery of an abandoned Manager session (CI-only)

Date: **2026-10-22**. Branch `dev/modernization-2026` (Draft PR #7). Tested code [`899245c6`](https://github.com/zlocorp/Portable-VirtualBox/commit/899245c6aa6b404a33522ed38503651ffb75e715). UI blocked-state follow-up [`a3681137`](https://github.com/zlocorp/Portable-VirtualBox/commit/a3681137e20fe86794372a3351192c54e602c675). No master merge, release or user-PC operations.

## What actually changed

A new **Recover** operation was added to the already compiled, pinned, narrowly scoped privileged helper. Its inputs are numeric live controller PID, former PID and former cycle, **not any path, script or command**. The helper verifies the new live controller's identity/hash/token, protected original `controller.json` and `session.json`, prior controller's complete absence (a recycled PID refuses recovery), same root and SID, 185 pinned Oracle files, and original protected scripts. It does not attempt recovery from incomplete or ambiguous acquisitions. A new C# recovery proof and a PowerShell `RecoverySession` receipt bind the original owner, current requester, protected VBoxSup/SDS reports, VM process absence and fresh service identity.

A separate **Recover abandoned session** button was added to the non-distributed Manager GUI, including RU/EN status, explicit asynchronous UAC request and fail-closed handling. The action stays available after normal Start was blocked by existing VBox resources. The ordinary six-member diagnostic preview does not include this helper or GUI.

## Real Windows evidence

- [**Successful orphan recovery 39761908190**](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39761908190), hosted **Windows Server 2022**: official Oracle 7.2.22 signed wrapper prepared, AutoIt 3.3.18.0 x64 frontend and compiled helper built, real signed VBoxSup/SDS registered.
- A new non-admin controller **could not recover** while the old controller remained alive. After the old controller exited, a direct `VBoxHeadless` blank VM started. Recovery was refused while this VM was running and VBoxSup stayed loaded.
- After explicit VM poweroff and verified zero remaining VBox processes, the new controller requested `Recover`. Cleanup returned **`cleanup_basis=RecoverySession`, `cleanup_verified=true`, `driver_package_removed=true`**, `final_vbox_services=[]`, no published INF or system driver, and protected code/app64 were removed. Existing VM configuration SHA-256 was unchanged.
- A second Recover attempt **refused replay**. The downloaded artifact `orphan-recovery-evidence` (ID `12418197101`) was checked against its JSON receipts; flags `live_owner_refused`, `live_guest_refused`, `original_vm_data_preserved`, `protected_payload_removed`, `orphan_recovery_verified` are all `true`.
- The first run [39761626623](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39761626623) exposed a **test-only PowerShell reserved `$Args` variable collision** and failed while creating the blank fixture VM. Fixed in [`899245c6`](https://github.com/zlocorp/Portable-VirtualBox/commit/899245c6aa6b404a33522ed38503651ffb75e715), re-ran the original real test unchanged apart from argument forwarding: success.
- Static Python: **148 tests, five platform skips, zero errors**; `check_active_tree.py` passed. Native policy and core build CI passed at `899245c6`. This is not substitute evidence for Windows 11 end users.

## Hard safety boundaries and outstanding acceptance

**No automatic cleanup.** Recovered session must have completed its original protected acquisition with valid receipts; an interrupted Prepare, partial cleanup or missing proof is deliberately **not** recoverable automatically. Only exactly scoped VBoxSup/SDS and the helper's protected staged application are removed, with active-guest/foreign-state refusal. All VM data and backups remain in the original user profile.

The test simulates an abandoned driver session by **gracefully exiting the original controller without issuing Finish**, not by forcibly crashing Windows or rebooting. There is no verified crash-during-driver-write recovery, Windows 11 standard-user or real interactive UAC approval/cancellation; no real guest OS/disk. The elevated CI invokes the new fixed helper directly. The user-facing launcher remains disabled. Do not describe Batch A as complete or distribute this experiment.

[Feature matrix](../FEATURES.md) · [Changelog](../CHANGELOG.md) · [Batch A plan](plans/2026-10-20-large-batch-delivery.md).
