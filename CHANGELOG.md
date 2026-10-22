# Changelog

User-relevant changes to the 2026 modernization. Format inspired by [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This is **not** an Oracle VirtualBox release log. No release numbers or public releases are implied by development checkpoints.

## [Unreleased]

### Added · 2026-10-22 offline portable-data safeguard (public preview)

- User-facing backup and independent verification for the entire portable `data/` tree (configuration, VM folders and snapshots stored there) through GUI and `--backup-data` / `--verify-backup` CLI, **without requiring VirtualBox, Python, elevation or hidden CI modes**.
- Backup creation refuses active/unknown VBox activity, a competing launcher session, unsafe/reparse paths, nested destinations and existing outputs; it hashes originals and copies using SHA-256, rescans source and publishes a completed folder only after verification.
- Long backups run in a separate ordinary-user process; GUI remains responsive and supports cooperative cancellation. Failed/interrupted work stays in `.pending` for inspection; no destructive cleanup or backup overwrite. The independent verifier checks hashes and rejects missing/extra/corrupt files.
- **Scope:** this is an offline **file copy** of `data/`, not an Oracle snapshot, media in external paths, VSS capture or automatic restore. The manifest is not signed. Existing VM launcher/UAC acceptance remains blocked.


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
