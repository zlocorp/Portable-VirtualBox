# Changelog

User-relevant changes to the 2026 modernization. Format inspired by [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This is **not** an Oracle VirtualBox release log. No release numbers or public releases are implied by development checkpoints.

## [Unreleased]

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
- Preview ZIP allowlist now includes **nine files**: EXE, warning, original license, both READMEs, CHANGELOG, FEATURES, CREDITS and THIRD_PARTY_NOTICES. Oracle and old tools remain excluded.

### Earlier modernization checkpoints · 2026-10-20 to 2026-10-21

These entries are reconstructed from the tracked execution reports, not retroactive release announcements.

- **Added:** RU/EN diagnostic GUI, UTF-8 CLI, explicit portable-folder setup, read-only host/process/service observations, bounded native commands, signed/hash-checked Oracle MSI/CAB preparation and lifecycle evidence.
- **Changed:** pinned Oracle test runtime from 7.2.20 to **7.2.22 r175245**; official external AutoIt **3.3.18.0** used for compilation.
- **Fixed:** stale-language readiness results, raw English status tokens in Russian diagnostics, incomplete language-key tests and misleading prepared-folder status when `app64` is absent.
- **Removed:** seven obsolete compiler/utility EXEs, fourteen old INI translations and splash artwork; the old audit requiring them. Modern `build.bat` delegates to `scripts/build.ps1`.
- **Verified only in disposable Windows Server CI:** empty-VM startup/poweroff, exact-owned VBoxSup/VBoxSDS teardown, repeat same-UUID fixtures and controlled relocation. See the dated execution reports for the version and limits of each run.

### Not released / not implemented

Normal-user Manager/VM Start/Stop, production UAC helper, Windows 11 end-to-end acceptance, guest OS/disk boot, general migration/crash recovery and transactional Oracle updates remain unfinished. They must not be listed as shipped advantages.

For every subsequent code change, update this log and [FEATURES.md](FEATURES.md). External sources require an entry in [CREDITS.md](CREDITS.md) and the adoption ledger; see [CONTRIBUTING.md](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/CONTRIBUTING.md).
