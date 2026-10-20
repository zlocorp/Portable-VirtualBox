# Inherited binary and language asset inventory (2026-10-20)

Compiled development executable uses official signed AutoIt **3.3.18.0** obtained directly in CI, and the experimental `app64` preparation is pinned to signed Oracle **VirtualBox 7.2.22** (build **175245**, released 2026-10-20). Both are the latest stable releases confirmed from the manufacturers' release pages on 2026-10-20.

## Current signed dependency pins (2026-10-20)

- **Oracle VirtualBox 7.2.22** (2026-10-20, maintenance/security release): official Windows installer `VirtualBox-7.2.22-175245-Win.exe`, SHA-256 `afd0ff1656cbe04ed88ce619594ae021419d97cce89fa9bdc443e9a963f1713f`. Independent [passive package inspection](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39497891196) verified **185 files / 247834716 bytes**, signatures, MSI version/platform, hash-consistent staged outputs and unchanged Windows services.
- **VBoxSup** from exactly that Oracle package: SYS `4d4af7a0bf01e97854d5bee9ee2bde9445aad408355bcfdae643f7eef7d523be`, INF `2fc48547de7dad96e3ebf0b49c339757317abd0c8a482f5f412a59fb730e05e4`, CAT `8e8c9dc09e518a75968ebf80174e33b77782c33baa4e71dafb637f6d6566ee9d`. These are *new* driver bytes, not compatible with 7.2.20 pins; runtime boot/teardown requires its own fresh CI result.
- **AutoIt 3.3.18.0** (released 2025-09-07) remains current. CI uses the official signed portable toolkit. We must not replace it with inherited 3.3.16.1.
- **7-Zip 26.04** (released 2026-10-05) is current, but the modern build **does not require 7z/7za at all**: the original unsigned 16.04 is retained only as quarantined legacy provenance.
- **DevCon:** Microsoft recommends built-in **PnPUtil**, which we already use for driver experiments. No standalone DevCon download should be bundled. **SnetCfg** is an obsolete, quarantined optional network-component tool; there is no active feature requiring an equivalent.
- Oracle **Extension Pack** is deliberately excluded pending explicit opt-in and license review. Guest Additions ISO is not a runtime prerequisite for the launcher.

Manufacturer references: [Oracle download index](https://download.virtualbox.org/virtualbox/7.2.22/), [AutoIt downloads](https://www.autoitscript.com/site/autoit/downloads/), [7-Zip downloads](https://www.7-zip.org/download.html), [Microsoft DevCon migration](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/devcon-migration).

## Actual committed historical executables

GitHub Actions job [39426115145](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39426115145) ran `scripts/audit_bundled_tools.ps1` (Get-FileHash, VersionInfo, Get-AuthenticodeSignature). Neither the script nor CI executes any inherited binary.

| Original file | Actual file version | Authenticode | Disposition |
| --- | --- | --- | --- |
| `source/Aut2Exe/Aut2exe.exe` | 3.3.16.1 | Valid (AutoIt Team) | Legacy only, replaced in CI by 3.3.18.0 |
| `source/Aut2Exe/Aut2exe_x64.exe` | 3.3.16.1 | Valid (AutoIt Team) | Legacy only |
| `source/i_data/tools/7za.exe` | 16.04 | NotSigned | Do not ship. Python+Windows API verified MSI/CAB preparation replaces it |
| `source/i_data/tools/devcon_x64.exe` | 6.1.7600.16385 (Win7 WDK) | NotSigned | Do not ship; test Windows driver API/PnPUtil use instead |
| `source/i_data/tools/devcon_x86.exe` | 6.1.7600.16385 (Win7 WDK) | NotSigned | Do not ship |
| `source/i_data/tools/snetcfg_x64.exe` | 5.2.3790.0 (Server 2003 DDK) | NotSigned | Do not ship; optional network feature postponed |
| `source/i_data/tools/snetcfg_x86.exe` | 5.2.3790.0 (Server 2003 DDK) | NotSigned | Do not ship |

**NotSigned** is a signature status, **not** proof of malware. It means these binaries cannot be treated as verified trusted runtime dependencies. Their hashes and publisher VersionInfo are retained in the short-lived CI artifact `inherited-tool-audit`.

Official sources: [Oracle VirtualBox](https://www.oracle.com/virtualization/technologies/vm/downloads/virtualbox-downloads.html), [AutoIt](https://www.autoitscript.com/site/autoit/downloads/), [7-Zip](https://www.7-zip.org/download.html). 7-Zip 26.04 is current as of October 20, 2026, but we have no technical need to bundle even its current executable. Optional compressed release formats can be evaluated later.

## Translation inventory

The original `source/i_data/language/` includes 14 historic INI translations. These describe tabs/features of the **archived legacy launcher** and are **not included in the active executable**; old Russian `russian.ini` contains broken, ambiguous and obsolete text. Do not patch this 15-year-old text and pretend to have modern translation.

New `source/LauncherI18n.au3` supplies explicit RU/EN translation keys to the modern preview GUI and CLI, with native test coverage. The app includes buttons to refresh, copy diagnostics and switch language, but **cannot start a VM yet**. Oracle's own VirtualBox Manager is a separate program with its own built-in language choices, documented [here](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/configuring-virtualbox.html). Later choose `ru` or `en` via the supported VBox property under the user's isolated portable profile; no binary patching of Oracle translations.

This repository currently ships no modern translated launcher ZIP, only development build artifacts. Legacy assets remain for provenance/attribution and should be excluded from release packaging by an explicit allowlist.
