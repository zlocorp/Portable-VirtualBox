# Active dependencies and retired upstream assets (updated 2026-10-21)

The current development branch is built from **official AutoIt 3.3.18.0**,
downloaded by CI or provided externally, and is tested against signed **Oracle
VirtualBox 7.2.22 r175245**. It does **not** include Oracle runtime executables
or drivers in the diagnostic preview ZIP. Normal GUI Start/Stop remains disabled.

## Required components

| Component | Current version | Origin and usage |
| --- | --- | --- |
| Oracle VirtualBox | **7.2.22 r175245** | Signed official installer, passively extracted to prepared `app64` in isolated tests; not bundled in this repository |
| AutoIt / Aut2Exe | **3.3.18.0** | Signed official compiler fetched separately in GitHub Actions; builds x64 launcher |
| Python 3 | Runner's supported version | Tests and safe MSI/CAB file-only extraction, not a packaged runtime executable |
| Windows PnPUtil | Provided by Windows | Scoped signed VBoxSup install/uninstall on disposable research hosts |

**Exact Oracle 7.2.22 package inputs (2026-10-20):** official
`VirtualBox-7.2.22-175245-Win.exe` SHA-256
`afd0ff1656cbe04ed88ce619594ae021419d97cce89fa9bdc443e9a963f1713f`.
The prepared x64 tree has **185 application files, 247834716 bytes**; package
signatures, MSI x64 identity, hashes and original host state were independently
checked in [Windows CI 39497891196](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39497891196).
The exact signed driver package pins are:
`VBoxSup.sys`: `4d4af7a0bf01e97854d5bee9ee2bde9445aad408355bcfdae643f7eef7d523be`;
`VBoxSup.inf`: `2fc48547de7dad96e3ebf0b49c339757317abd0c8a482f5f412a59fb730e05e4`;
`VBoxSup.cat`: `8e8c9dc09e518a75968ebf80174e33b77782c33baa4e71dafb637f6d6566ee9d`.
The real compiled AutoIt blank-VM boot and exact-owned cleanup passed on a
disposable Windows Server 2022 host ([CI 39498269366](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39498269366)).
This is **not** Windows 11 or standard-user UAC acceptance.

## Removed from the active repository tree

The obsolete upstream binaries and language assets were not required by the
modern build and were **deleted from the active branch**, not merely omitted
from the distributed preview:

| Historical input | Version / description | Replacement |
| --- | --- | --- |
| `source/Aut2Exe/Aut2exe.exe`, `Aut2exe_x64.exe` | AutoIt **3.3.16.1** | External signed **3.3.18.0** |
| `source/i_data/tools/7za.exe` | **16.04**, unsigned | Python/Windows MSI/CAB extraction; no archive executable |
| `source/i_data/tools/devcon_x64.exe`, `devcon_x86.exe` | Win7 WDK **6.1.7600.16385**, unsigned | Built-in Windows **PnPUtil** for approved driver experiments |
| `source/i_data/tools/snetcfg_x64.exe`, `snetcfg_x86.exe` | Server 2003 DDK **5.2.3790.0**, unsigned | No active network driver feature; don't install by default |
| `source/i_data/language/*.ini` | Fourteen archived, outdated translations | Compiled modern RU/EN catalog `source/LauncherI18n.au3` |
| `source/i_data/settings/SplashScreen.jpg` | Historical legacy splash art | Not used by modern GUI |

**No executable or language file was moved into a release archive.** Git history
and the upstream source still preserve their origin. Old
`source/legacy/Portable-VirtualBox.au3.disabled` remains for historical
inspection, deliberately uncompiled and potentially referring to retired
files. The original author/license in `LICENSE.md` remain intact. A static
`python scripts/check_active_tree.py` check and CI guard reject reintroduction
of obsolete resources or an old batch build command.

The previous [signed-file inventory CI 39426115145](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39426115145)
is historic evidence only; the former audit script that **required** old files
was also removed. **NotSigned** meant unsigned, not malware.

Current upstream 7-Zip **26.04** exists but is *not* needed or bundled. DevCon
and SnetCfg likewise require no version upgrade because they are absent from
the shipping architecture. Optional USB, bridged-network drivers and Oracle
Extension Pack remain deferred to explicitly reviewed features.

## Localization and build

Modern launcher RU and EN translations are embedded in
`source/LauncherI18n.au3`, independent of the 14 archived INI files. Native
Windows tests cover localized diagnostic values, readiness messages and
locale-switch refresh. Oracle VirtualBox Manager has its **own** language
setting in the private portable profile.

Root `build.bat` delegates to `scripts/build.ps1`; `BUILDING.md` now
documents the supported Windows x64 process. Packaging is a strict allowlist
of six diagnostic-only ZIP members (including bilingual READMEs and consolidated credits) and **never includes Oracle or drivers**.

References: [Oracle releases](https://download.virtualbox.org/virtualbox/7.2.22/),
[AutoIt official downloads](https://www.autoitscript.com/site/autoit/downloads/),
[7-Zip](https://www.7-zip.org/download.html),
[Microsoft DevCon migration](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/devcon-migration).

See [active-tree cleanup execution report](EXECUTION-2026-10-21-dependency-cleanup.md).
