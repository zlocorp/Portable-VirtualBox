# Portable-VirtualBox · 2026 modernization

[Русский](README.ru.md) · [Features](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/FEATURES.md) · [Changelog](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/CHANGELOG.md)

A modernization of [vboxme/Portable-VirtualBox](https://github.com/vboxme/Portable-VirtualBox), focused on a small bilingual launcher, verifiable dependencies and portable user data.

> **Development preview, not an approved everyday VM launcher.** Normal double-click does not install drivers or start VMs. An explicitly opted-in ALPHA and a CI-only path use the integrated real Oracle Manager, but Windows 10/11 workstation UAC and driver installation acceptance remain pending. Real Alpine Linux x86-64 boot and VDI writes have passed isolated Windows Server CI.

**First-run setup without installed Python.** Click **Prepare VirtualBox / folders**: **Yes** downloads pinned Oracle VirtualBox 7.2.22 over official HTTPS, **No** selects an already-downloaded installer. The separate non-admin `Portable-VirtualBox-Setup.exe` checks its built-in SHA-256 and prepares `app64` without executing an MSI or installing drivers. Existing `app64` is not overwritten. CLI: `--download-app64` or `--prepare-app64 "INSTALLER_PATH"`. Both routes passed [compiled Windows acceptance](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40209800549). Download progress shows transferred MiB (and a percentage when Oracle provides its content length), then separate verification/extraction phases. The status is informational; only the validated app64 receipt marks success.

## What is different

**Offline portable-data backups and fresh-root recovery.** The ordinary GUI now offers an asynchronous backup/verification action for the entire `data/` tree, with cancellation, SHA-256 checks for each copied file and a non-overwriting `.pending` staging folder. The backup and restore actions never touch drivers, VM processes or Oracle configuration. Restoring always creates a fresh, separate folder; existing files are never merged or overwritten. Copying is blocked while VirtualBox is active. **This is a backup of files under `data/`, not a live VM snapshot:** disk images/media outside `data/` are not included. Interrupted stages are preserved for inspection; use a separate drive for important backups. A restored root contains only portable data and its checksum manifest: supply a launcher and Oracle app64 separately before attempting to run VMs.

**Safe planning before repairing a moved VM.** Use `Portable-VirtualBox.exe --plan-vm-rebind` to preview one recoverable stale entry in `VirtualBox.xml`, and `--prepare-vm-rebind "NEW_BACKUP_FOLDER"` to create a verified, non-overwriting SHA-256 copy of the whole portable `data/` tree. The planner requires the original registered path to be genuinely absent, matching VM UUID at the new root, every disk/snapshot file local and readable, no second VM, no reparse points and no running or unknown VBox components. It never runs Oracle, changes registration, edits XML or installs drivers. The separate **Repair moved VM** action in the experimental Manager window performs the explicitly confirmed registration repair described below.

**Read-only discovery for several moved VMs.** The existing **Audit VM portability** GUI button now also displays this report when the multi-VM candidate is valid, including after RU/EN switching or refreshing. It never adds a batch repair action.  `Portable-VirtualBox.exe --plan-multi-vm-rebind` reports **2–16** registered machines apparently relocated together from the same absent former portable root. It checks per-VM UUID/path identity, safe machine configuration, local disk/snapshot/ancillary files, absence of saved-state references, registry/configuration hashes and idle-host observations. Exit **0 means a reviewable report, not approval to repair**; 2 means no multi-VM candidate; 3 means an unsafe/unknown case; 64 means invalid syntax. No Oracle command, registry rewrite, backup or batch repair is performed. Keep the original data and an independent verified backup. The existing `--prepare-vm-rebind` and ALPHA `Repair moved VM` still authorize **one VM only**. Physical cross-host movement and transactional multi-VM recovery are not accepted.

**Verified full backup for several moved VMs.** Once `--plan-multi-vm-rebind` reports a reviewable 2–16 VM candidate, run `Portable-VirtualBox.exe --prepare-multi-vm-rebind "NEW_BACKUP_FOLDER"` to create a **new, non-overwriting, offline SHA-256 copy of the entire `data/` tree**. The tool uses the existing backup engine, independently verifies the manifest, then rechecks the registry SHA-256, every VM's reported configuration hash, inventory and idle-host state. It returns `BACKUP_ONLY`, not a registration-repair authorization. Exit 0 means **only the backup was verified**; 2 means blocked or no batch candidate, 3 means incomplete/uncertain backup, 64 means invalid arguments. If the result is uncertain, preserve the completed or `.pending` folder for inspection; never treat it as a repair permit. No bulk Oracle command, XML rewrite or elevated action is added.

**Partial multi-VM registration recovery (read-only).** After creating the original verified full copy, `Portable-VirtualBox.exe --review-multi-vm-rebind "ORIGINAL_BACKUP"` compares that immutable backup with the current registry and complete VM data. It labels every original UUID `STALE`, `ABSENT` or `LOCAL`, and displays a possible next stage **as an informational hint, never an Oracle command**. A valid all-local set reports `COMPLETE` and does not suggest repeating operations. Unknown/foreign/duplicate registrations, modified VDI/snapshot bytes, changed .vbox files, an invalid backup, an existing old source or active VirtualBox activity block the report. Exit 0 means only a valid observation; exit 3 means blocked; 64 means invalid arguments. The separate one-VM repair remains unchanged. **This command does not perform the next stage or authorize any multi-VM writes.**

**Recovery step/trace verification is still read-only.** Native Windows regression tests now bind the expected next UUID and action to the complete original ordering, unchanged .vbox SHA-256 evidence, and an actual change of global registry SHA-256 across each observed step. A partial trace is never a complete repair; replay, skipped register, reordering and hidden UUIDs are refused. This does **not** write an authenticated transaction journal or enable any new Oracle action. Batch repair remains unavailable pending owner-bound execution/recovery and workstation UAC acceptance. The existing privileged helper now keeps a separate protected, flushed journal of each `Prepare`/`Finish`/`Recover` attempt, distinguishing intent, worker exit and completed helper checks. This is diagnostic durability infrastructure, not a multi-VM step journal or permission to replay interrupted operations.

**Check VM portability before copying.** Use the RU/EN **Audit VM portability** GUI action or `--audit-vms` to inspect local `.vbox` configurations, snapshot counts, external/missing virtual disks and machine registrations in `data/.VirtualBox/VirtualBox.xml`. An external registered VM or unregistered `.vbox` file is shown as needing review. Backing up `data` with such findings requires explicit GUI confirmation or prints a CLI warning. External disks are **never included** in that copy. This read-only check does not modify VM XML and does not guarantee that a backup is complete.

**A usable diagnostic shell.** Native Russian/English GUI and UTF-8 CLI, remembered language with an explicit “Save language” action, a return to Windows language selection, readable failure reasons, copyable diagnostics and a concise About window. A temporary `--lang` selection never overwrites the saved preference.

**Russian localization, verified in isolated Windows CI.** Session/rebind refusals now provide Russian explanations while retaining exact diagnostic identifiers. Live language switching retranslates backup hints/results without changing operation state, and compact backup buttons support wrapped captions. Service names, JSON fields, internal state tokens and original Oracle diagnostics stay invariant.

**Oracle Manager language.** An explicitly saved launcher `ru`/`en` preference is applied on the next full prepared-session start, using ordinary-token `VBoxManage setextradata global GUI/LanguageID` and a strict read-only postcondition. English maps to Oracle's built-in `C`. Auto/missing/invalid preferences and a temporary `--lang` override do not overwrite a separately selected Oracle preference. Reopening Manager while a guest is active does not change language. No manual XML rewrite or privileged verb is added. Preparation and readiness require nonempty `nls/VirtualBox_ru.qm` and `nls/qt_ru.qm` from the same pinned Oracle package, not a third-party language download.

At `3301638`, [compiled launcher checks](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/41537264954) passed RU -> EN -> RU switching, measured button bounds and read-only behavior; all three launcher screenshots were reviewed. [Real Oracle/Alpine acceptance](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/41537257180) verified Russian first start, Russian reopen with a live guest and English second start using actual menu/button captions and inspected screenshots, while retaining guest VDI readback, snapshots, repair and cleanup. The snapshots also show Oracle's USB-enumeration warning; USB passthrough remains deferred. This is not full-DPI or interactive Windows 10/11 UAC acceptance. Native Windows dialogs follow the host OS language; Oracle's bundled translations determine its own translation completeness.

**Service snapshots for troubleshooting and tests.** `--diagnose-services` prints the same RU/EN ten-service inventory used in the GUI; `--diagnose-services-json` emits locale-independent schema 1 (`services`, `exit_code`). Each JSON row contains only `name`, `observation`, `state`, `win32_error` and `ownership`. Starting/stopping/pausing/resuming states remain visible in this read-only snapshot; strict runtime checks still require two identical stable observations. Error 1060 at service-open means absent; access denial or an unavailable result stays unknown. Non-absent ownership is `UNVERIFIED`, never inferred from a service name. No private image/account paths, COM activation, profile creation or system actions. Exit 0 means known observations, **not readiness or permission to clean**; 4 means unknown and 64 means invalid arguments.

**Portable Oracle CLI in ALPHA.** The paired `VBoxManage.cmd` / `VBoxManagePortable.exe` uses this root's `data\.VirtualBox` and the verified protected Oracle runtime, never an installed fallback. Start the ALPHA Manager session first and run commands from a non-elevated terminal. A live-controller/session check and native command lease coordinate with cleanup; before Prepare, during cleanup and after Finish the adapter refuses commands. It preserves arguments, working directory and Oracle exit codes. This is not a VM safety sandbox: Oracle commands can change user data, although `unregistervm --delete` is explicitly refused. The ordinary diagnostic ZIP does not include the adapter. See [ALPHA instructions](docs/ALPHA-WINDOWS-TEST.md).

**No bundled obsolete executables.** Old AutoIt compilers, 7za, DevCon, SnetCfg, fourteen legacy translation INIs and the old splash were removed. The build uses official external AutoIt **3.3.18.0**. The tested Oracle package is pinned to **7.2.22 r175245**, with exact hashes, publisher checks and file-only MSI/CAB preparation rather than silently running an installer.

**Supported target host family:** Oracle VirtualBox 7.2 supports Windows 10/11 x64 workstations. The launcher preflight now accepts **Windows 10 build 19041+** and Windows 11, while rejecting Server editions, ARM64 and unknown hosts. This is a compatibility policy, not a Windows 10/11 runtime acceptance claim. See Oracle's [official supported-host list](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/installation.html).

**Checks that distinguish failure states.** Missing directories, incomplete `app64`, inaccessible/reparse paths, existing installations and unknown host observations are not treated as “ready”. The application inspection names missing or empty required EXEs, DLLs and VBoxSup files. Presence alone is explicitly **not** a signature check or permission to launch.

**Portable user preferences and data.** Explicit first-run creation of `data/.VirtualBox`, `data/Machines` and `logs` preserves existing files. The only preference file is `data/launcher.ini`; malformed/foreign settings are not overwritten. Saving uses a same-directory staged replacement and refuses stale `.pending` files. No Oracle XML is rewritten by these public features.

**Manager and guests are not the same process.** Diagnostics separately report Manager, GUI/headless guest processes and background activity. These are observations, not proof that a guest is running or permission to stop/delete anything.

## Portable-root relocation and snapshot chains

Powered-off VirtualBox VMs with **snapshot/differencing VDI media** now survived four real disposable Windows tests: moving the Unicode directory and changing a test VHDX from `P:` to `Q:`, both with a clean prior unregister and with an **old absolute registration left in VirtualBox.xml**. Oracle's official unregister/register operations restored the same VM and snapshot UUIDs, identical virtual-disk hashes and new-root media paths without deleting the files. [Four-mode Windows evidence](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40462477639). The ordinary VM audit remains read-only. Experimental repair requires a separately selected verified backup and explicit confirmation; use no valuable VM for ALPHA acceptance.

### Explicit repair and interrupted registration

The experimental Manager window offers **Repair moved VM** for one powered-off VM with a fully local snapshot/media chain. Create the full backup while the stale registration still exists. Select that existing backup, inspect the displayed UUID, old/new paths and backup folder, then explicitly confirm. The controller verifies the same proof again before requesting driver preparation and runs Oracle `unregistervm` without `--delete`, followed by `registervm`. Cancel or No leaves registration and system resources unchanged. Normal diagnostic double-click and the planning/backup CLI remain unable to perform these system operations.

If the operation stopped after unregistering, keep the original backup. First finish any required **Recover abandoned session** cleanup so no former controller, guest or driver session remains active. Select the same backup in **Repair moved VM** again. A missing registry entry is accepted only when the backup identifies the original stale UUID and the VM files still match; that route performs **register only**. An already-correct registration needs no change. Ambiguous or changed VM data is refused, and the backup is never overwritten. Saved-state migration, multiple-VM repair and arbitrary power-loss recovery remain outside this acceptance. Current Windows results are tracked in [Draft PR #7](https://github.com/zlocorp/Portable-VirtualBox/pull/7); hosted Server tests do not establish interactive Windows 10/11 safety.

## Workstation alpha, isolated testing only

A separate, **non-release** developer candidate can be launched with
`Portable-VirtualBox.exe --alpha-runtime` on an isolated Windows 10/11 x64
workstation. Its exact-build helper asks for UAC only for driver/service
operations; the Oracle Manager and VMs remain non-elevated. The normal
double-click preview is still diagnostic-only and does not bundle this helper.
No interactive Windows 11 UAC acceptance has been performed. See
[alpha acceptance instructions](docs/ALPHA-WINDOWS-TEST.md), not a production
installation guide.

## Try the current preview

Double-click the compiled launcher for the GUI, or use the ordinary CLI:

```powershell
Portable-VirtualBox.exe --lang ru --help
Portable-VirtualBox.exe --save-language ru
Portable-VirtualBox.exe --save-language auto
Portable-VirtualBox.exe --prepare-profile
Portable-VirtualBox.exe --download-app64
Portable-VirtualBox.exe --prepare-app64 "D:\Downloads\VirtualBox-7.2.22-175245-Win.exe"
Portable-VirtualBox.exe --app-status
Portable-VirtualBox.exe --check-readiness
Portable-VirtualBox.exe --diagnose
Portable-VirtualBox.exe --diagnose-services
Portable-VirtualBox.exe --diagnose-services-json
Portable-VirtualBox.exe --audit-vms
Portable-VirtualBox.exe --plan-vm-rebind
Portable-VirtualBox.exe --plan-multi-vm-rebind
Portable-VirtualBox.exe --prepare-multi-vm-rebind "D:\Backups\Moved-VMs-original"
Portable-VirtualBox.exe --review-multi-vm-rebind "D:\Backups\Moved-VMs-original"
Portable-VirtualBox.exe --prepare-vm-rebind "D:\Backups\Moved-VM-original"
Portable-VirtualBox.exe --about
Portable-VirtualBox.exe --backup-data "D:\Backups\PortableVBox-2026-10-22"
Portable-VirtualBox.exe --verify-backup "D:\Backups\PortableVBox-2026-10-22"
Portable-VirtualBox.exe --restore-backup "D:\Backups\PortableVBox-2026-10-22" "E:\Restored-VBox-Data"
```

`--save-language ru|en|auto` explicitly creates portable data folders when needed. Other inspection commands do not create them. `--app-status` returns 0 for required nonempty files present, 2 for absent `app64`, and 3 for incomplete/unsafe files. `--check-readiness` returns 3 for a blocker or 2 when preflight is clear but this build's runtime is disabled. Neither exit code enables a VM.

For `--audit-vms`, exit code **0** means no detected portability flags, **2** means review needed or no registered VMs, and **3** means invalid/unsafe observations. None of these is Oracle integrity certification.

A damaged `launcher.ini` is left intact and the launcher falls back to the Windows language. Inspect a stale `launcher.ini.pending` before removing it; it can be evidence of an interrupted write. Do not overwrite a working VirtualBox installation with this preview.

The 2026-10-22 VM audit extension passed [compiled x64 RU/EN and file-only backup regressions](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39793670380), [23 native AutoIt harnesses](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39793670330) and [actual Oracle 7.2.22 machine-registry/VM boot/teardown](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39793670384). These tests ran on disposable Windows Server, **not interactive Windows 11**.

## Manager session integration (experimental)

**Recovery after interrupted driver preparation (experimental):** Protected, owner-bound checkpoints now also allow exact-owned rollback after VBoxSup **Stage**, **Start** or VBoxSDS **registration**, *before* the normal session receipt exists. [Three clean-host rollback and forged-receipt CI scenarios](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39778793621) demonstrated all three phases, rejected live-owner/missing-receipt/replayed operations and refused both a forged VBoxSup stage receipt and a forged VBoxSDS registration marker without changing services or VM data. No speculative cleanup if a system operation was interrupted *before* the corresponding receipt. This is CI-only, not approved end-user recovery; no interactive Windows 11/UAC acceptance.

**Recovery after an abandoned session (experimental):** the separate test GUI now offers an explicit recovery action when a prior protected session remains. The fixed helper independently rejects a still-live original controller, active VMs, foreign/stale receipts and replay; it cleans only exactly owned VBoxSup/SDS and protected staging after positive verification. [Real disposable-host proof](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39761908190) preserved the VM's configuration across recovery. No automatic cleanup, production UAC/Windows 11 approval, power-cut/reboot or arbitrary mid-operation recovery, or release is implied.

The ordinary compiled EXE contains **Start VirtualBox / Finish session / Reopen Manager** controls, enabled on disposable CI hosts or through explicit `--alpha-runtime` with the paired helper on an isolated workstation. [Windows GUI acceptance](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39567202279) opened the real Oracle Manager, kept an empty VM running after Manager closed, reopened Manager, refused a second controller, and completed two cleanups with the same VM UUID. The ordinary diagnostic ZIP does not enable system operations. Later helper tests run Manager/guests with a medium token, while interactive workstation UAC approval and cancellation still require acceptance. [Evidence and limitations](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/docs/EXECUTION-2026-10-21-manager-session.md).

## Evidence and limits

Data backups are folders containing `data/` plus `SHA256SUMS.txt`; failed/cancelled operations leave `*.pending` in place, not a misleading finished copy. SHA-256 detects accidental corruption but the manifest is not cryptographically signed. Only **offline** files in the portable `data/` directory are included. Do not infer that VMs with external disks are fully backed up or automatically restorable.


[FEATURES.md](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/FEATURES.md) is the current capability matrix: **public preview**, **CI-only**, **planned**. [CHANGELOG.md](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/CHANGELOG.md) records user-relevant changes under **Unreleased**, not fictional product releases.

The community-adoption implementation `183f35da` passed [x64 build, ordinary compiled CLI and ZIP checks](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39548219426), [18 native AutoIt harnesses](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39548219415) and [compiled empty-VM boot plus exact-owned driver teardown](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39548214487). The downloaded preview ZIP was independently inspected: its checksum matches, and credits, notices and both READMEs are included. [Full evidence and environment limits](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/docs/EXECUTION-2026-10-21-community-adoption.md).

**Not yet production-verified:** ordinary-user Manager Start/Stop, interactive workstation UAC approval/denial, general VM relocation and power-loss recovery, transactional Oracle updates, optional USB/bridged networking. Actual Alpine guest boot and VDI disk I/O **are** verified on a disposable Windows Server CI host ([proof](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40407596523)); Windows 11 UAC and everyday-host safety are **not**.

## Build and packaging

See [build instructions](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/BUILDING.md). `build.bat` delegates to `scripts/build.ps1`; Python runs tests and builds the diagnostic ZIP. Oracle, drivers and VM data are never bundled in that ZIP. The seven-file allowlist contains the launcher, standalone file-only preparation helper (with embedded Python), preview warning, original license, both READMEs and one consolidated CREDITS file. Developer feature/changelog/adoption documents remain in the repository.

## Authors and license

Based on upstream snapshot `5b58dbbe701c3e2eb348942a9059708063b0cb96`. Original author credits, including **Michael Meyer (michaelm_007) and contributors** and the **vboxme project**, are retained. This modernization is maintained in **zlocorp/Portable-VirtualBox**.

The original **CC BY-NC-SA 3.0** license remains unchanged; see [LICENSE.md](LICENSE.md). Sources, authors and external-component notices are consolidated in [CREDITS.md](CREDITS.md). No affiliation with or endorsement by Oracle, AutoIt or community authors is implied.
