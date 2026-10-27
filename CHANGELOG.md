# Changelog

User-relevant changes to the 2026 modernization. Format inspired by [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This is **not** an Oracle VirtualBox release log. No release numbers or public releases are implied by development checkpoints.

## [Unreleased]

### Added · user-facing moved-VM plan and verified offline backup (2026-10-27)

- The **ordinary compiled main EXE** now offers `--plan-vm-rebind` (read-only, bilingual) and `--prepare-vm-rebind NEW_BACKUP_FOLDER`. Its normal GUI VM audit displays an exact stale-entry candidate. The planner accepts only a single relocated VM whose original `MachineEntry` points to an absent old local root and whose UUID matches an existing new-root `.vbox`; it checks all local media and snapshots, forbids foreign/unknown VBox activity, duplicate/unregistered machines, junctions and DTD/XXE.
- Backup preparation uses the established durable, SHA-256 verified full `data/` copier, refuses overwrites, then rechecks the source VM, registry identity and hashes. **Neither operation runs VBoxManage, edits VirtualBox.xml or changes a Windows driver/service.** Completing the user-approved Oracle re-registration remains a separate release gate.

### Fixed · reject pre-existing unowned VBoxSup driver leftovers (2026-10-27)

- Signed VBoxSup staging now refuses a host that has the kernel image in `System32\drivers` or a previously published OEM INF referencing VBoxSup, **even if no VBox service/Oracle installation is currently registered**. The scan reads Windows INF data as possible ANSI/UTF-8 and UTF-16LE before the first `pnputil` mutation. This closes an ownership ambiguity that could otherwise adopt and later delete a foreign/stale package. No service/driver deletion is performed by the preflight.

### Extended protected-user guest I/O acceptance (2026-10-27)

- The **main EXE** in the existing medium-token/privileged-helper Windows CI matrix now receives the same verified official Alpine Linux x86-64 ISO as ordinary user data. It exercises real Oracle VBoxHeadless under medium integrity while *only the pinned helper* runs elevated, refuses cleanup during live guest execution, performs an Alpine `dd` to the attached portable VDI, then powers off and confirms no process/service survives the first protected teardown. During the second protected session it clones the same VDI to a temporary RAW file, requires the exact Linux-written bytes, creates a powered-off snapshot and verifies its differencing VDI. This remains **direct-helper CI**, not interactive Windows 11 UAC acceptance; results are not claimed until the actual Windows run succeeds.

### Added · recovery probe for already-relocated VM registrations (2026-10-27)

- Two further disposable Windows matrix variants simulate moving the USB-root folder or reassigning its VHDX drive letter **without first unregistering** an existing powered-off VM. The moved `VirtualBox.xml` retains the stale former absolute `MachineEntry`. At the new location, the fixture inspects the exact old UUID, requests supported Oracle `unregistervm` **without `--delete`**, checks that .vbox/base/differencing VDI bytes survive and re-registers the same UUID and snapshot chain under the new root. This is non-production research, intended to establish a safe recovery sequence before adding any opt-in ordinary-user relocation tool.

### Fixed · Oracle mixed-separator snapshot Location display (2026-10-27)

- Both real Windows relocation variants already preserved VM UUID, powered-off snapshot UUID and byte-identical base/differencing VDI files, but the final medium-graph assertion falsely failed: Oracle printed the differencing VDI `Location:` as `Snapshots/{uuid}.vdi` inside an otherwise backslash-separated Windows path. The test now normalizes separators **only in read-only VBoxManage output**, never in .vbox/VirtualBox.xml data. Snapshot identity checks also match the explicit `SnapshotUUID` field rather than any UUID in a transcript. Full new-root VBoxSDS teardown still has to be verified by the rerun.

### Expanded removable-root portability acceptance (2026-10-27)

- The existing isolated Windows directory-move and test-VHDX P: -> Q: relocation matrix now creates a real Oracle powered-off snapshot with differencing VDI before `unregistervm` (never `--delete`). After moving the **entire** portable root, it re-registers the unchanged VM via Oracle's supported CLI and requires the same VM/snapshot UUIDs, byte-identical base/differencing VDI files, new-root medium graph paths and exact VBoxSDS cleanup. Timed-out VBoxManage, signed VBoxSDS and VHDX DiskPart operations retain their native subprocess handles until exit rather than killing live state mutations. This is still CI-only research pending successful two-mode Windows acceptance and explicit user-consent relocation tooling.

### Extended guest VDI read/write acceptance (2026-10-27)

- The existing real Alpine Linux GUI test now sends an isolated fixed login/write sequence through Oracle's virtual PS/2 keyboard. The Linux guest must write a unique marker to sector 2048 of the already attached empty VDI; after power-off, exact-owned driver cleanup and a second Manager session, the test clones the disk to a temporary RAW readback and verifies the actual bytes at that sector before reporting guest-OS disk I/O success. Screenshots alone cannot satisfy this assertion. RAW test copies are removed and never included in a distribution. [Real compiled-main-EXE Windows #40407596523](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40407596523) **passed**: 64-bit Alpine login, executed guest `dd` (30-byte write), matched RAW sector bytes after driver teardown and second Manager session; VDI, same VM UUID, powered-off snapshot and clean VBoxSup/VBoxSDS after two cycles. Confirmed from downloaded GUI proof and guest console screenshot. Windows 11 interactive UAC is still untested.

### Fixed · explicit ALPHA exit after indeterminate system failure (2026-10-27)

- A failed Manager/helper session is **not** evidence of driver cleanup. ALPHA no longer lets closing its session window silently return to the main GUI after a FAILED state. With no live helper handle, exit requires an explicit warning that VirtualBox services and guests may remain; confirming leaves protected receipts and exits the entire original controller for subsequent careful recovery. The CI-only experiment keeps its existing automation semantics.

### Fixed · Alpine guest x86-64 CPU configuration (2026-10-27)

- [Actual main GUI ISO screenshot 40405065168](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40405065168) exposed a genuine guest startup error despite green lifecycle CI: Oracle's Other VM default reported `longmode="off"`, so Alpine 64-bit stopped on an i686 CPU check. The existing CI fixture now requests Linux_64, enables x86 long mode and checks the independent Oracle machine-readable report for `longmode="on"` before accepting guest-display capture. A VM running state and screenshot alone do not prove the OS booted.

### Fixed · do not orphan native driver operations after safety deadline (2026-10-27)

- All five existing protected Windows driver/SDS native-command paths now retain their exact spawned process after the normal timeout and wait for confirmed termination before releasing helper ownership locks. Former `Kill()` calls on PnPUtil / service control could interrupt live system modifications; one partial-recovery timeout previously discarded an active child handle. A late native exit now remains a **failure requiring protected-receipt inspection**, never inferred success or arbitrary cleanup. Main GUI stays responsive through its separate user/privileged worker processes.

### Extended real guest OS acceptance · 2026-10-27

- The existing isolated main-EXE Manager/VDI/snapshot Windows workflow now mounts the official version-fixed Alpine Linux 3.24.3 virtual ISO (SHA-256 compared to the release's official HTTPS manifest) as a **guest-only** optical disk, starts the headless VM and captures the actual guest display via Oracle's supported `VBoxManage controlvm screenshotpng`. This adds a visual guest-boot witness without inventing another VM runner or shipping ISO/guest files to users. The screenshot still needs inspection before claiming a booted Linux system or guest disk writes.

### Fixed · window X cannot abandon an in-flight helper (2026-10-26)

- Closing the Manager session with the native window X or Alt+F4 now uses the **same** live-helper guard as the disabled Close button. Before this fix the system-close event could bypass the disabled control, exit a failed session and leave a privileged worker in-flight. All close requests are now ignored while the exact worker handle remains active; no driver cleanup or process termination is guessed.

### Fixed · cleanup UAC refusal and unknown worker lifetime (2026-10-26)

- A denied Finish UAC no longer turns a Close click into another automatic elevation prompt. Close instead requires an explicit warning/confirmation that own system components will remain; it then exits the **entire original controller** so a fresh alpha session can use its protected one-shot Recover. The ordinary Finish button still retries the exact-owned cleanup immediately.
- A pending or unknown worker is retained and re-observed even after its normal deadline; the launcher does not report completion or allow Close while a privileged operation might still mutate Windows. Transient handle-observation races are retried without guessing success or terminating processes.

### Fixed · real Manager worker exit-race (2026-10-26)

- One actual compiled Manager Start/Stop CI run hit `worker-not-confirmed-UNKNOWN` after successfully staging VBoxSup and writing the protected session receipt. A fast child can exit between the retained-handle wait and Windows read-only identity query. ManagerSession now re-observes the **same process handle** for at most five seconds; only a confirmed exit and zero code advance the session, while persistent unknown remains fail-closed. No process-name lookup, termination or guessed cleanup was added.

### Added · isolated Windows workstation alpha (2026-10-26)

- The existing main launcher now has an **explicit developer opt-in** `--alpha-runtime`, separate from ordinary double-click. It uses the existing protected driver/Manager lifecycle and a helper bound to the exact compiled EXE hash. The elevated helper independently refuses non-workstation or non-x64 Windows, checks the original process/user integrity and pins Oracle. Alpha receipts use a separate `%ProgramData%/PortableVirtualBox.Alpha` store. The diagnostic ZIP remains nonprivileged and unchanged.
- An isolated-host candidate ZIP is built as a temporary **Actions artifact**, **not a release**; it contains the ordinary main EXE, non-admin frozen Oracle Setup, paired alpha helper, README RU/EN, attribution/license and a SHA256 manifest. It includes no Oracle binaries or user VM files. On hosted Windows Server the CI test must prove both alpha entrypoints refuse all system effects.
- **Not yet accepted:** human UAC approval/cancel on Windows 11, real workstation driver operations, guest OS disk I/O and power-cut recovery. Only disposable Windows client hosts should be used for manual acceptance.

### Fixed · CI VM poweroff confirmation race (2026-10-26)

- A genuine disposable-host run found a transient VBoxManage exit code 1 immediately after a successful guest power-off. The compiled AutoIt VM acceptance now waits up to 30 seconds for a read-only `showvminfo` result with the same UUID and `poweroff` state before issuing its boot receipt or allowing exact-owned cleanup. A still-running or unknown VM is never treated as stopped.

### Fixed · Windows 10/11 host compatibility (2026-10-26)

- Corrected read-only host preflight to support **Windows 10 x64 build 19041+**, alongside Windows 11 x64. Oracle VirtualBox 7.2 lists both client OS families as supported hosts. Server editions, unsupported older builds and ARM64 are still rejected. Updated native policy checks, startup self-test and RU/EN diagnostics. No driver operations were enabled by this change.

### CI-bound main EXE UAC transport · 2026-10-25

- The unattended, noninteractive Windows UAC regression now launches the **actual ordinary compiled main EXE** with a medium user token, clicks its own Manager/Start controls, and follows its real same-EXE request-worker to ShellExecuteExW runas. The test requires the GUI to remain responsive in CONSENT_PREPARE with no VBox service/driver effects. It does not approve/cancel the secure-desktop dialog and cannot replace interactive Windows 11 testing.
- The earlier separate session-test frontend is retained for focused helper and recovery regressions, not used to substitute for the main app's UAC request.

### Verified · 2026-10-25 refused forged recovery receipts on PowerShell 5.1

- The real Windows Server recovery check proved normal Stage/Start/Sds recovery after the UTF-8 fix. Forged driver and SDS receipts were **already refused by the elevated worker**; the assertions had incorrectly failed because Windows PowerShell 5.1 wrapped error messages across display lines. The test now normalizes only log whitespace, not ownership data, and still verifies real services/VM files remain untouched after refusal.

### Fixed · 2026-10-25 Unicode-safe privileged recovery

- Windows PowerShell 5.1 interpreted BOM-less UTF-8 JSON receipts produced by the elevated C# helper using the system ANSI code page. Cyrillic portable-root paths then appeared to be different owners, blocking legitimate interrupted driver recovery. All protected JSON reads now explicitly request UTF-8, preserving exact owner/path comparisons. Refusal remains strict for forged/stale records, and the existing one-shot recovery tests run on isolated Unicode-path hosts.

### Fixed · 2026-10-25 Windows PowerShell process tracking

- Windows PowerShell 5.1 exposed a real process-tracking incompatibility: Start-Process -NoNewWindow -PassThru with redirected output can return an empty ExitCode after waiting, despite successful driver staging. The fixed elevated scripts now cache each exact subprocess handle immediately, before waiting. All confirmation still depends on verified zero exit codes and signed driver/service receipts; no guessed success or relaxed service checks.

### Reliability · 2026-10-25 system-worker lifetime and dependency

- The fixed elevated helper uses the built-in **64-bit Windows PowerShell** from System32 instead of requiring an separately installed PowerShell 7. It continues to run only the embedded, hash-checked fixed-action scripts inside the protected session; no PATH lookup, downloaded scripts, or arbitrary commands.
- If an elevated action exceeds its normal 150-second deadline, the helper **retains and waits for its real system-worker handle** before reporting failure and releasing the effect lock. The ordinary GUI's non-admin UAC request worker likewise no longer marks a still-live elevated helper finished after an arbitrary 180-second timeout. Owner loss never becomes a success response.
- CI exercises the actual protected service/driver lifecycle with these changes. This is not approval of interactive Windows 11 UAC or a shipping runtime.

### Expanded Windows acceptance · 2026-10-25 real VM media

- The disposable main-EXE GUI Start/Stop fixture now creates a real Oracle 64 MiB VDI under portable `data/Machines`, attaches it to the test VM, checks it survived driver removal, and then creates a powered-off Oracle snapshot on the second session, verifying its differencing files after teardown.
- [Isolated compiled-main-GUI Windows acceptance 40220863138](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40220863138) **passed**: real Oracle Manager/VM, VDI created and preserved, snapshot created and differencing medium retained, guest-aware Manager reopening and two exact-owned cleanups. An empty guest with a real VDI is **not** a booted Windows/Linux guest OS; interactive Windows 11 UAC remains unverified.

### Integrated experiment · 2026-10-25 main EXE privilege boundary

- The fixed-action helper can now bind the exact compiled **main** frontend as well as the separate experiment ([medium-token acceptance passed 40220863135](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40220863135)): build-time controller name/SHA-256 and Oracle inventory are verified before any system mutation. Its privileged worker accepts only the compiled-in controller identity, never caller-supplied paths or commands.
- On disposable Windows CI only, a medium-token normal EXE is routed to the existing separated manager/UAC controller, with the already-elevated CI path unchanged. The direct-invoker helper regression now tests both compiled frontends on separate isolated hosts; it does not simulate or claim interactive Windows 11 UAC.
- No helper is added to the public preview ZIP, no release is published, and normal-host Start/Stop stays blocked pending reviewed production effects.

### Improved · 2026-10-25 first-run progress

- First-run download now reports verified transfer progress in MiB and percentage when Oracle provides Content-Length; SHA-256 validation and app64 extraction have separate RU/EN status messages. The temporary status is written only by the non-admin preparer to a fresh reserved file and removed after completion/failure; it is never used as integrity or privilege evidence.
- File-only setup stays non-overwriting, and Start/Stop is unavailable during active preparation. This does **not** enable VM Start/Stop for ordinary Windows 11 users.

### Added · 2026-10-25 first-run Oracle preparation

- The ordinary GUI offers two choices: download exact pinned Oracle VirtualBox 7.2.22 from official HTTPS, or select a local official installer. Public CLI: `--download-app64` / `--prepare-app64 INSTALLER`. Standalone non-admin Setup EXE embeds Python; Oracle MSI and drivers are never executed or installed. Existing `app64` is never overwritten.
- [Compiled Windows acceptance https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40209800549](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40209800549) verified both paths, 185 files, repeated-preparation refusal and no system driver/service changes. Diagnostic ZIP contains seven files, including Setup. **Production Start/Stop and interactive Windows 11 UAC remain unverified.**


### Added / fixed · 2026-10-22 VM portability and safer repeat start

- Ordinary RU/EN GUI and `--audit-vms` now read `.vbox` configurations, count snapshots and identify local, missing or external virtual-disk paths. The extended inventory checks `data/.VirtualBox/VirtualBox.xml`: it flags registered VMs outside portable data, locally saved but unregistered machines, and invalid/missing registration information. XML DTD/external entities and reparse points are rejected; no VM files are rewritten.
- File-only `data` backup now prompts in the GUI or warns in the CLI when an audit indicates potentially incomplete VM data. External VM disks remain excluded and success does not certify complete VM backup.
- Fixed experimental Manager repeat-start race after verified cleanup: retain the session lock until 2.5 seconds of known-empty host state; retry a temporary existing-VBox blocker only through explicit full preflight. [Real Manager GUI regression 39791350463](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39791350463) passed two cycles with the same VM UUID.
- Initial VM inventory [native AutoIt 39790407525](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39790407525), [compiled RU/EN CLI 39790408168](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39790408168), and [actual Oracle 7.2.22 `.vbox` 39791602687](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39791602687) passed. Global-registry extension `e8732507` passed [native AutoIt 39793670330](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39793670330) (23 harnesses, including 40 VM-inventory assertions), [compiled RU/EN x64 39793670380](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39793670380) and [real Oracle 7.2.22 empty-VM/registry/driver teardown 39793670384](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39793670384). None validates interactive Windows 11 UAC or external-disk backup.


### Added / verified · 2026-10-22 interrupted driver preparation recovery

- Implemented **protected one-shot prepare checkpoints** in the separate compiled helper. A prepared, pinned Oracle runtime records an original controller-bound `prepare-intent.json` before system effects; after actual signed VBoxSup INF staging, verified driver Start, and explicit VBoxSDS registration, their distinct protected receipts support a narrowly scoped `Recover` even without the usual committed `session.json`.
- New `vbox_sup_partial_cleanup.ps1` verifies live Windows state against the exact original pinned driver, published OEM INF and signed VBoxSDS image, original-controller departure, currently authorized same-user recovery controller, no running VBox/VM processes, exact receipt ancestry, and no previous cleanup. It stops/removes only the proven-owned service/package, rejects unknown state and does not use `pnputil /force` or global process-name kills.
- The existing **Recover after failure** action also discovers an interrupted protected preparation. A new Start refuses an abandoned protected session rather than overwriting its evidence. No automatic elevated action is performed.
- [Real Windows Server 2022 signed-driver CI **39776758692**](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39776758692): **PASS** for actual Stage, Start and Sds interruption/recovery; old-controller/live-owner denial, missing stage receipt denial, replay denial, clean services/INF afterward and preserved user fixture data. Downloaded and independently inspected 94 evidence files: top-level proof reports `validated_checkpoints=["Stage","Start","Sds"]`, `unauthorized_cleanups=0`, `all_owned_services_removed=true`, and individual receipts report `cleanup_basis=PartialRecovery`.
- [Three isolated disposable Windows test jobs **39778793621**](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39778793621) verified positive Stage/Start/Sds cleanup **and two adversarial refusals**. Forged protected VBoxSup install report and VBoxSDS registration marker each caused **refusal before a system modification**; the remaining driver/service state and VM-data hashes were preserved. Each refusal runs on its own disposable host because once quiescence was recorded, replay must stay denied even if an administrator edits the receipt. Downloaded and inspected all three proof archives.
- **Not claimed:** recovery during incomplete driver installation **before** a durable verified stage receipt, arbitrary in-flight SDS registration, unexpected foreign Windows resources, physical reboot/power loss, interactive Windows 11 UAC/consent or a production build. Unknown cases continue to require manual inspection.


### Added / verified · 2026-10-22 abandoned Manager session recovery (CI-only)

- A separately compiled, fixed-action elevated helper accepts an **explicit** `Recover` request for one old `PID + cycle`, with a new medium-token controller. It independently checks protected original controller/session receipts, same user and pinned launcher/runtime, expired controller PID, service/driver identity and **zero running VirtualBox processes** before removal. No unknown path or user-supplied shell commands are accepted.
- Added a **Recover abandoned session** action in the non-distributed RU/EN Manager GUI. Recovery can be requested even after a blocked normal Start. It is never automatic and still requires UAC consent on a real interactive machine.
- Added one-shot `RecoverySession` proof to the existing signed `VBoxSup`/`VBoxSDS` teardown. Unknown, missing, partial or replayed records **refuse cleanup** and preserve resources for inspection. It does not unlock arbitrary driver deletion.
- [Actual Windows driver/empty-VM acceptance 39761908190](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39761908190) **passed**: refuse with original controller live, refuse with test VM still running after controller exit, power off VM, recover only own resources, prove all services/INF/driver files gone, preserve original VM configuration, and refuse replay. The downloaded proof explicitly reports `cleanup_basis=RecoverySession`, `cleanup_verified=true`, `driver_package_removed=true`, `interactive_uac_verified=false`.
- **Scope:** This validates a *complete, prepared, abandoned* session on a disposable Windows Server 2022 host. Not a simulated power cut, partial driver install, interrupted cleanup, a real guest OS with disk or interactive Windows 11/UAC acceptance. No user release, no automatic cleanup and no master change.


### Added · 2026-10-22 offline portable-data safeguard (public preview)

- User-facing backup, independent verification and fresh-root restoration for the entire portable `data/` tree (configuration, VM folders and snapshots stored there) through GUI and `--backup-data` / `--verify-backup` / `--restore-backup` CLI, **without requiring VirtualBox, Python, elevation or hidden CI modes**.
- Backup creation refuses active/unknown VBox activity, a competing launcher session, unsafe/reparse paths, nested destinations and existing outputs; it hashes originals and copies using SHA-256, rescans source and publishes a completed folder only after verification.
- Long backups run in a separate ordinary-user process; GUI remains responsive and supports cooperative cancellation. Failed/interrupted work stays in `.pending` for inspection; no destructive cleanup or backup overwrite. The independent verifier checks hashes and rejects missing/extra/corrupt files. Restoring accepts only a verified backup and writes to a nonexistent destination; it never merges with or overwrites an existing user VM.
- **Scope:** this is an offline **file copy** of `data/`, not an Oracle snapshot, media in external paths, VSS capture or automatic re-registration of VMs. The manifest is not signed. Existing VM launcher/UAC acceptance remains blocked.


### Verified privilege separation experiment · 2026-10-21

- Added a fixed-purpose elevated helper, protected validated Oracle runtime copy and ordinary-integrity Manager/guest execution to the **non-distributed** session experiment. Tested exact-input refusal, protected-write denial, live-guest cleanup refusal and two complete owned cleanup cycles: [Windows Server 2022 run 39649261984](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39649261984) **passed**.
- Kept the actual GUI `ShellExecuteExW runas` consent path separate. [Run 39649261666](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39649261666) **failed** at the tampered-payload step: frontend remained `IDLE` after logging `Elevation request: Prepare cycle=1`. This is consistent with an unavailable interactive consent desktop but **does not prove that as root cause**. UAC cancellation/consent, progress while elevation is pending, and production Windows 11 end-to-end remain open.
- Direct helper invocation by the elevated disposable harness is **not equivalent to UAC delivery**. No production launcher or ZIP includes these experimental effects. Do not downgrade this acceptance requirement or replace `runas` with silent elevation.


### Added / fixed · 2026-10-21 integrated Manager session

- Adapted the Manager/guest lifecycle flow from ThatAdminGuy and upstream PR #90 into actual **Start / Finish session / Reopen Manager** buttons in a separate experimental frontend, using the existing signed VBoxSup/VBoxSDS operations rather than duplicating an installer.
- Retain exact process handles; send a normal window-close request, never terminate VirtualBox by process name. Closing Manager leaves a running GUI/headless VM and its driver intact; Manager can be reopened while the VM continues.
- A second launcher session refuses to interfere. Cleanup requires the session's original receipts, a matching live controller generation and fresh absence of VBox activity. Manager-only cleanup has its own quiescence evidence and does not pretend a VM was booted.
- Fixed an observed early-close race: wait for a visible, enabled Manager window with stable geometry before posting close, avoiding the tested Oracle geometry-save/COM-teardown error without suppressing its dialogs.
- [Actual Windows GUI acceptance](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39567202279) pressed the compiled buttons, opened Oracle Manager, preserved a running empty VM across Manager close/reopen, refused a second controller, cleaned two sessions and preserved the UUID/configuration.
- **Scope:** this separate EXE is not in the six-file diagnostic ZIP. Its effect worker still requires an already elevated disposable Windows Server runner. Production UAC/Windows 11 acceptance and ordinary-user Start/Stop remain unfinished.

### Changed · 2026-10-21 attribution simplification

- About now shows only the product, project address, license/notice location and runtime status, without a contributor roster.
- Consolidated external-component notices into `CREDITS.md`; removed the duplicate `THIRD_PARTY_NOTICES.md`. Original `LICENSE.md` and source notices are unchanged.
- Diagnostic ZIP now contains **six files**: EXE, preview warning, two READMEs, LICENSE and CREDITS. CHANGELOG, FEATURES and detailed adoption records remain in the repository rather than duplicating developer material in the user package.
- Suitable fork code is reused and adapted directly when it fits; only a concrete incompatibility justifies replacement. Lists of ideas do not count as implemented behavior.

### Added · 2026-10-21 community-adoption package

- Explicit saved RU/EN launcher language and “Windows language” reset; GUI buttons and `--save-language ru|en|auto`. Preference is local to the portable root and survives relocation. Inspired by **Deac2** first-run/settings UX; independently implemented.
- Read-only `--app-status` and GUI readiness inspection of all 15 required EXEs/DLLs/VBoxSup inputs, rather than treating a lone `VirtualBox.exe` as a complete application. Reports the exact missing/empty filenames. Motivated by upstream **#103/#105**; no external code copied.
- Exact missing portable-folder names, including `data/Machines`, in readiness errors. Regression scenario from **Deac2/upstream #92**.
- Separate Manager, GUI/headless guest-process and background-process diagnostic counts. Scenario from **ThatAdminGuy** and **skyshay001/upstream #90**. This is not yet the production shutdown controller.
- Compiled About dialog and `--about`; project/community attribution also travels inside the preview ZIP.
- English/Russian READMEs, a capability matrix, explicit community-adoption ledger, credits and third-party notices.

### Changed

- Explicit language saving stages a small versioned file in `data/launcher.ini.pending`, flushes it and replaces only a recognized launcher configuration in the same directory. Read-only commands and temporary `--lang` do not persist anything. Unknown schema, foreign files and stale pending files are refused; this is not a claim of power-loss recovery.
- Readiness result is scrollable so a long missing-file list is accessible.
- At the first adaptation checkpoint the preview ZIP included **nine files** (subsequently reduced above): EXE, warning, original license, both READMEs, CHANGELOG, FEATURES, CREDITS and THIRD_PARTY_NOTICES. Oracle and old tools remain excluded.

### Earlier modernization checkpoints · 2026-10-20 to 2026-10-21

These entries are reconstructed from the tracked execution reports, not retroactive release announcements.

- **Added:** RU/EN diagnostic GUI, UTF-8 CLI, explicit portable-folder setup, read-only host/process/service observations, bounded native commands, signed/hash-checked Oracle MSI/CAB preparation and lifecycle evidence.
- **Changed:** pinned Oracle test runtime from 7.2.20 to **7.2.22 r175245**; official external AutoIt **3.3.18.0** used for compilation.
- **Fixed:** stale-language readiness results, raw English status tokens in Russian diagnostics, incomplete language-key tests and misleading prepared-folder status when `app64` is absent.
- **Removed:** seven obsolete compiler/utility EXEs, fourteen old INI translations and splash artwork; the old audit requiring them. Modern `build.bat` delegates to `scripts/build.ps1`.
- **Verified only in disposable Windows Server CI:** empty-VM startup/poweroff, exact-owned VBoxSup/VBoxSDS teardown, repeat same-UUID fixtures and controlled relocation. See the dated execution reports for the version and limits of each run.

### Not released / not implemented

Normal-user Manager/VM Start/Stop, production UAC helper, Windows 11 end-to-end acceptance, guest OS/disk boot, general migration/crash recovery and transactional Oracle updates remain unfinished. They must not be listed as shipped advantages.

Record user-visible changes here and update [FEATURES.md](FEATURES.md) when capability status changes. Actual external reuse belongs in [CREDITS.md](CREDITS.md); detailed research stays in the adoption record; see [CONTRIBUTING.md](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/CONTRIBUTING.md).
