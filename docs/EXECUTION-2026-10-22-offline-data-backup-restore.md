# Offline portable data backup and recovery | 2026-10-22

Working branch: `dev/modernization-2026`, PR #7 (Draft). Tested implementation: [`c244669d`](https://github.com/zlocorp/Portable-VirtualBox/commit/c244669d16c995a2deed9553caae0d89b12f7ae4); test assertion correction: [`bfa340aa`](https://github.com/zlocorp/Portable-VirtualBox/commit/bfa340aa1ab0a2b0f2347380a5aad2032ab88e15). Historical master and published releases unchanged.

## Public user workflow now implemented

The ordinary signed-external-AutoIt-compiled, diagnostic-only GUI now includes **Back up portable data**, **Verify backup**, **Restore to new folder** and **Cancel copy**. All file work is done by a child of the ordinary user's own launcher, without privilege elevation, driver installation, external 7za, Python runtime or Oracle executables.

CLI: `--backup-data "D:\Backups\new-backup"`, `--verify-backup "D:\Backups\new-backup"`, `--restore-backup "D:\Backups\new-backup" "E:\new-portable-root"`.

- Source is the **entire `data/` tree**, including portable VirtualBox configuration, machines and snapshots **when physically stored under `data/`**. Logs, executables, externally referenced VM disks and media outside `data/` are deliberately not copied. This is *not* a live snapshot or a guarantee of bootability of every external-medium VM.
- Creation and restore refuse existing targets, any ancestor/nested source/target relationship, path collisions/reparse points, active/unknown VirtualBox processes/services and competing portable launcher session. The existing shared Manager-session mutex is held through copy and publication.
- Copy and restore stage into a new adjacent `.pending` folder. All regular files are copied and SHA-256 hashed; original data is rescanned, finished backup is independently verified, and publication uses same-volume `MoveFileExW` without overwrite. On cancel/failure, the stage is **retained** for inspection and never falsely published as a complete copy.
- `--verify-backup` independently recomputes per-file hashes, rejects duplicate, missing, corrupt, unexpected or unsafe file paths. Backups are **not signed** or protected from a malicious user who can rewrite both the backup and its manifest. A restored destination contains `data/` and `SHA256SUMS.txt` only, with no VirtualBox binaries or driver effects.

## Actual tests

| Test | Result |
| --- | --- |
| [Core Windows x64 + real compiled public CLI **39748483539**](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39748483539) | **SUCCESS**. Copied a synthetic Unicode VM configuration and nested snapshot file, verified SHA-256, restored into a fresh root, independently verified restored bytes, refused target overwrite, detected source-backup tampering, built and tested the six-file preview ZIP without old tools or Oracle binaries. |
| [Retested core on assertion-fix head **39748621019**](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39748621019) | **SUCCESS**. Complete ordinary x64 pipeline, including public backup and restore script. |
| [Native AutoIt **39748620974**](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39748620974) | **SUCCESS**. 22 native harnesses, zero failures; new offline backup/restore fixture had **28 assertions, zero failures**; exhaustive language catalog 259 checks, zero failures. |
| [Pinned Oracle preparation **39748627214**](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39748627214) | **SUCCESS**; the new ordinary user feature did not require or modify the Oracle 7.2.22 preparation workflow. |
| Local Linux Python source/tests | 144 discovered, 139 passed, five platform skips, zero failures. These are supplementary, not substitutes for Windows execution. |

The initial Windows build rejected an obsolete RU warning assertion after adding real backup functionality. Replaced that assertion with a check for the actual localized wording and reran full CI. No functional code or security check was removed to make the build green.

## Boundaries / next gates

This is a substantial **public user-data safety feature**, not production VM-launch acceptance. No real guest OS with disk was run in this backup test; synthetic data was intentionally used to keep it independent of driver behavior. No signed restore manifest or VSS snapshot is claimed, no external media are captured and no registry/Oracle XML edits or automatic VM registration are performed.

Production normal-user Manager/VM Start/Stop, interactive Windows 11 UAC approval/cancel, crash/reboot repair of exact-owned driver registrations and full guest OS/media-chain acceptance remain separate incomplete milestones.
