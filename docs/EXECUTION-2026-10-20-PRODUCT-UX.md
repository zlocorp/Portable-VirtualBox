# Product UX and legacy dependency modernization checkpoint

Date: 2026-10-20. Modernization branch only; no merge into master or release.

## User-facing changes

Added:
- `source/LauncherI18n.au3`: embedded launcher RU/EN localization with Russian locale auto-detection (`@OSLang`) and explicit `--lang ru`, `--lang en`, `--help` CLI selection. Preflight blocking reasons and diagnostic labels have translated variants. This is a **new** catalog, not the historical unused `russian.ini`.
- `source/LauncherGui.au3`: new read-only Win32 GUI for double-click launches. It displays system diagnostics, RU/EN radio language switching, refresh, copy report and close. No fake Start/Stop controls and no privilege requests. VM launch remains DISABLED.
- `HostDiagnostics.au3` shares the same localized diagnostic collector between CLI and GUI. Default diagnostic remains redacted (no process executable paths or service account names).
- Russian stdout uses UTF-8 conversion rather than direct AutoIt `ConsoleWrite` conversion through the host ANSI page.
- Isolated configuration fixture exercises Oracle's *own* documented `VBoxManage setproperty language ru` under a private `VBOX_USER_HOME`. The call succeeds. Oracle Manager visual translation itself was not rendered or screenshot-tested.

## Executed proof

The initial Cyrillic UTF-8 CLI acceptance check **failed** at [CI run 39426464437](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39426464437) because AutoIt direct console output uses the Windows ANSI code page. After adding the UTF-8 writer, [CI run 39427042843](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39427042843) passed and checked the actual decoded contents of `--lang ru --help` and `--lang ru --diagnose`. It also compiled x64, executed safety diagnostics and built in a Cyrillic path.

[Native AutoIt CI 39427042438](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39427042438): 10 compiled test harnesses, **448 assertions**, including 97 localized string/host-locale checks; zero failures.

[Oracle/Windows regression CI 39427042456](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39427042456) and core Linux CI both discovered **98 Python tests**, with one Windows symlink privilege skip and five Windows-only Linux skips, zero failures; official 185-file Oracle `app64` preparation still passes.

[Isolated Oracle preference test 39427583563](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39427583563): `setproperty language ru` exited zero, and the profile/VM definition checks passed.

**Not yet verified:** localized GUI screenshot/spacing/keyboard accessibility on interactive Windows 11, supported driver lifecycle from the new GUI, or running an actual guest OS.

## Actual inherited-tool metadata

[CI 39426115145](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39426115145) read version, SHA-256 and signature data without executing any legacy EXE:

- Bundled `Aut2exe.exe` and `Aut2exe_x64.exe`: 3.3.16.1, Valid signature; CI uses separately fetched official signed **3.3.18.0**.
- `7za.exe`: **16.04**, NotSigned; modern preparation uses Python/Windows MSI/CAB APIs. Official 7-Zip has version **26.04** (2026-10-05), but no 7-Zip executable is currently required.
- `devcon_x64.exe` and `devcon_x86.exe`: **6.1.7600.16385**, NotSigned; do not ship. Tested newer staging via Microsoft PnPUtil/Windows APIs instead.
- `snetcfg_x64.exe` and `snetcfg_x86.exe`: **5.2.3790.0** (Windows Server 2003 DDK), NotSigned; obsolete network features remain disabled.

Signature absence is not evidence of malicious behavior; it makes their trust/provenance unsuitable for unreviewed new packaging. Keep these historical resources for reference but exclude them by explicit allowlist from eventual releases.

## Forward plan and release gates

See [PRODUCT-PLAN-2026-10-20.md](PRODUCT-PLAN-2026-10-20.md) for the actionable P0–P5 roadmap. The next critical implementation is the **minimum functional safe AutoIt launcher**: first-run data folders, signed-driver preflight, explicit privileged startup, opening VirtualBox Manager, graceful wait/stop, exact-owned cleanup and useful RU/EN status. After that add user-facing update checking/staging/rollback, optional network/USB drivers, and small integration PRs. This is substantially higher priority than more generic coordinator research.

Existing `master` and the legacy archive remain untouched. Draft PR #7 remains the research vehicle, not a mergeable release candidate. No Oracle executables or drivers have been redistributed in this commit.
