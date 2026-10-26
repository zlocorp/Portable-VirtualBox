# Portable-VirtualBox · 2026 modernization

[Русский](README.ru.md) · [Features](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/FEATURES.md) · [Changelog](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/CHANGELOG.md)

A modernization of [vboxme/Portable-VirtualBox](https://github.com/vboxme/Portable-VirtualBox), focused on a small bilingual launcher, verifiable dependencies and portable user data.

> **Development preview, not a usable VM launcher yet.** The normal GUI does not start VirtualBox Manager or VMs and does not install drivers. Actual driver/empty-VM tests run only on disposable Windows CI hosts. Windows 11 standard-user/UAC acceptance is still pending.

**First-run setup without installed Python.** Click **Prepare VirtualBox / folders**: **Yes** downloads pinned Oracle VirtualBox 7.2.22 over official HTTPS, **No** selects an already-downloaded installer. The separate non-admin `Portable-VirtualBox-Setup.exe` checks its built-in SHA-256 and prepares `app64` without executing an MSI or installing drivers. Existing `app64` is not overwritten. CLI: `--download-app64` or `--prepare-app64 "INSTALLER_PATH"`. Both routes passed [compiled Windows acceptance](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40209800549). Download progress shows transferred MiB (and a percentage when Oracle provides its content length), then separate verification/extraction phases. The status is informational; only the validated app64 receipt marks success.

## What is different

**Offline portable-data backups and fresh-root recovery.** The ordinary GUI now offers an asynchronous backup/verification action for the entire `data/` tree, with cancellation, SHA-256 checks for each copied file and a non-overwriting `.pending` staging folder. The backup and restore actions never touch drivers, VM processes or Oracle configuration. Restoring always creates a fresh, separate folder; existing files are never merged or overwritten. Copying is blocked while VirtualBox is active. **This is a backup of files under `data/`, not a live VM snapshot:** disk images/media outside `data/` are not included. Interrupted stages are preserved for inspection; use a separate drive for important backups. A restored root contains only portable data and its checksum manifest: supply a launcher and Oracle app64 separately before attempting to run VMs.

**Check VM portability before copying.** Use the RU/EN **Audit VM portability** GUI action or `--audit-vms` to inspect local `.vbox` configurations, snapshot counts, external/missing virtual disks and machine registrations in `data/.VirtualBox/VirtualBox.xml`. An external registered VM or unregistered `.vbox` file is shown as needing review. Backing up `data` with such findings requires explicit GUI confirmation or prints a CLI warning. External disks are **never included** in that copy. This read-only check does not modify VM XML and does not guarantee that a backup is complete.

**A usable diagnostic shell.** Native Russian/English GUI and UTF-8 CLI, remembered language with an explicit “Save language” action, a return to Windows language selection, readable failure reasons, copyable diagnostics and a concise About window. A temporary `--lang` selection never overwrites the saved preference.

**No bundled obsolete executables.** Old AutoIt compilers, 7za, DevCon, SnetCfg, fourteen legacy translation INIs and the old splash were removed. The build uses official external AutoIt **3.3.18.0**. The tested Oracle package is pinned to **7.2.22 r175245**, with exact hashes, publisher checks and file-only MSI/CAB preparation rather than silently running an installer.

**Supported target host family:** Oracle VirtualBox 7.2 supports Windows 10/11 x64 workstations. The launcher preflight now accepts **Windows 10 build 19041+** and Windows 11, while rejecting Server editions, ARM64 and unknown hosts. This is a compatibility policy, not a Windows 10/11 runtime acceptance claim. See Oracle's [official supported-host list](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/installation.html).

**Checks that distinguish failure states.** Missing directories, incomplete `app64`, inaccessible/reparse paths, existing installations and unknown host observations are not treated as “ready”. The application inspection names missing or empty required EXEs, DLLs and VBoxSup files. Presence alone is explicitly **not** a signature check or permission to launch.

**Portable user preferences and data.** Explicit first-run creation of `data/.VirtualBox`, `data/Machines` and `logs` preserves existing files. The only preference file is `data/launcher.ini`; malformed/foreign settings are not overwritten. Saving uses a same-directory staged replacement and refuses stale `.pending` files. No Oracle XML is rewritten by these public features.

**Manager and guests are not the same process.** Diagnostics separately report Manager, GUI/headless guest processes and background activity. These are observations, not proof that a guest is running or permission to stop/delete anything.

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
Portable-VirtualBox.exe --audit-vms
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

The ordinary compiled EXE contains **Start VirtualBox / Finish session / Reopen Manager** controls, currently enabled only on disposable CI hosts. [Windows GUI acceptance](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39567202279) opened the real Oracle Manager, kept an empty VM running after Manager closed, reopened Manager, refused a second controller, and completed two cleanups with the same VM UUID. This is **not included in the diagnostic ZIP**: its system adapter still requires an already elevated disposable runner, not a production UAC flow. [Evidence and limitations](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/docs/EXECUTION-2026-10-21-manager-session.md).

## Evidence and limits

Data backups are folders containing `data/` plus `SHA256SUMS.txt`; failed/cancelled operations leave `*.pending` in place, not a misleading finished copy. SHA-256 detects accidental corruption but the manifest is not cryptographically signed. Only **offline** files in the portable `data/` directory are included. Do not infer that VMs with external disks are fully backed up or automatically restorable.


[FEATURES.md](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/FEATURES.md) is the current capability matrix: **public preview**, **CI-only**, **planned**. [CHANGELOG.md](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/CHANGELOG.md) records user-relevant changes under **Unreleased**, not fictional product releases.

The community-adoption implementation `183f35da` passed [x64 build, ordinary compiled CLI and ZIP checks](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39548219426), [18 native AutoIt harnesses](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39548219415) and [compiled empty-VM boot plus exact-owned driver teardown](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39548214487). The downloaded preview ZIP was independently inspected: its checksum matches, and credits, notices and both READMEs are included. [Full evidence and environment limits](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/docs/EXECUTION-2026-10-21-community-adoption.md).

**Not implemented:** production Manager Start/Stop, reviewed privilege-separated UAC helper, general VM migration, power-loss and arbitrary mid-driver-operation recovery, transactional Oracle updates, optional USB/bridged networking. No real guest OS/disk or interactive Windows 11 GUI/DPI acceptance is claimed. A Linux/Windows Server CI pass is not Windows 11 approval.

## Build and packaging

See [build instructions](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/BUILDING.md). `build.bat` delegates to `scripts/build.ps1`; Python runs tests and builds the diagnostic ZIP. Oracle, drivers and VM data are never bundled in that ZIP. The seven-file allowlist contains the launcher, standalone file-only preparation helper (with embedded Python), preview warning, original license, both READMEs and one consolidated CREDITS file. Developer feature/changelog/adoption documents remain in the repository.

## Authors and license

Based on upstream snapshot `5b58dbbe701c3e2eb348942a9059708063b0cb96`. Original author credits, including **Michael Meyer (michaelm_007) and contributors** and the **vboxme project**, are retained. This modernization is maintained in **zlocorp/Portable-VirtualBox**.

The original **CC BY-NC-SA 3.0** license remains unchanged; see [LICENSE.md](LICENSE.md). Sources, authors and external-component notices are consolidated in [CREDITS.md](CREDITS.md). No affiliation with or endorsement by Oracle, AutoIt or community authors is implied.
