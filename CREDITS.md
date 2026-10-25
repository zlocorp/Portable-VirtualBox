# Credits and notices

**Portable-VirtualBox** is based on [vboxme/Portable-VirtualBox](https://github.com/vboxme/Portable-VirtualBox), snapshot `5b58dbbe701c3e2eb348942a9059708063b0cb96`.
Original source credits: **Michael Meyer (michaelm_007) and contributors**, and the **vboxme / Runar Buvik** project. The **2026 modernization by zlocorp** modifies that work; it is not an official upstream or Oracle release. Original notices and the **CC BY-NC-SA 3.0** license are preserved in [LICENSE.md](LICENSE.md).

## Community references and adaptations

| Source | Use |
| --- | --- |
| [Deac2](https://github.com/Deac2/Portable-VirtualBox), [PR #92](https://github.com/vboxme/Portable-VirtualBox/pull/92) | Settings/language UX and missing-folder/relocation scenarios, independently adapted in the modern launcher. |
| [ThatAdminGuy, a035d06b12](https://github.com/ThatAdminGuy/portable-virtualbox/commit/a035d06b12), [skyshay001, PR #90](https://github.com/vboxme/Portable-VirtualBox/pull/90) | Manager/guest startup and shutdown flow adapted in `ManagerSession.au3` and `ManagerWindow.au3`; unsafe shell/name waits replaced with retained process handles and guest-aware cleanup. Tested in a separate disposable-host GUI, not yet a production UAC launcher. |
| [bitamind, 4ffc9e097f](https://github.com/bitamind/Portable-VirtualBox/commit/4ffc9e097f) | Oracle-specific VBoxSDS registration commands, used as a research reference for our CI lifecycle. |

The modern adaptations above were implemented independently; their source links are not claims of copied code. Detailed issue references, historical translation work and pending ideas remain in the repository's [adoption record](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/docs/COMMUNITY-ADOPTION.md). Direct future code imports must retain their original notices and identify local changes.

## External components

- **AutoIt**, Jonathan Bennett and the AutoIt Team: [official site](https://www.autoitscript.com/site/autoit/) and [license](https://www.autoitscript.com/autoit3/docs/license.htm). An official external compiler builds this EXE; compiler/toolkit binaries are not bundled. Existing include-file headers remain intact.
- **Oracle VirtualBox**: a separately obtained runtime with its own [licensing](https://www.virtualbox.org/wiki/Licensing_FAQ). No Oracle EXE, DLL, driver, Guest Additions or Extension Pack is included in this preview ZIP.
- **Python (PSF license)**: the standalone `Portable-VirtualBox-Setup.exe` includes an embedded Python runtime and standard-library modules. Users do not need Python separately. [License](https://docs.python.org/3/license.html).
- **PyInstaller**: an external build tool for that Setup EXE; its bootloader is part of the compiled executable. [Licensing and distribution exception](https://pyinstaller.org/en/stable/license.html).
- **PowerShell and Windows APIs/PnPUtil** are development/host dependencies and are not shipped as extra executables. The inherited project icon remains unchanged; no community artwork was imported.

These notices do not change third-party licenses or imply endorsement by any named author or vendor.
