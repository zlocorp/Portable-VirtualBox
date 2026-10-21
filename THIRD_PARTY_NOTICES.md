# Third-party notices

This document records provenance and distribution boundaries. It does not relicense third-party software or substitute for the relevant original licenses.

| Material | Relationship to this preview | Notice / source |
| --- | --- | --- |
| Original Portable-VirtualBox | Inherited project basis and retained original assets/source headers | [vboxme upstream](https://github.com/vboxme/Portable-VirtualBox); original **CC BY-NC-SA 3.0** text is retained in `LICENSE.md`. Attribution and modifications: `CREDITS.md`. |
| AutoIt and Aut2Exe | Official external compiler used to build the EXE; AutoIt runtime is part of compiled output; upstream-derived include files retain their headers | [AutoIt](https://www.autoitscript.com/site/autoit/), [official licensing](https://www.autoitscript.com/site/autoit/autoit-license/). The toolkit/compiler itself is not bundled. Do not apply the project's license to AutoIt's components. |
| Oracle VirtualBox / VBoxSup / VBoxSDS | Separately fetched, signed and pinned developer/CI dependencies | [Oracle VirtualBox](https://www.virtualbox.org/). No Oracle EXE, DLL, driver, Guest Additions ISO or Extension Pack is included in this preview ZIP. Any later redistribution needs a separate license/package review. |
| Windows APIs / PnPUtil / PowerShell | Host-provided APIs or external test/build tools | [Microsoft Windows documentation](https://learn.microsoft.com/en-us/windows/). No Windows utility or driver binary is redistributed here. |
| Python standard library | Used by developer tests, passive package preparation and ZIP creation | [Python](https://www.python.org/). Python itself is not included in the preview ZIP or required by the ordinary compiled diagnostic UI. |
| Community PRs/forks | Ideas, bug reports and independently adapted behavior | Exact authors, sources and adoption categories appear in `CREDITS.md` and the community ledger. This package does not import their compiled binaries or direct runtime code. |

The original project's icon is retained from the upstream baseline; no new Oracle/community artwork was imported by the 2026-10-21 adoption package. The old splash, compiler binaries, 7za, DevCon, SnetCfg and legacy translation INIs were removed from the active tree.

The names Oracle, VirtualBox, Microsoft and AutoIt identify their respective products. This is an independent development fork, not an official or endorsed distribution. A successful CI run is not a license review or a security certification.
