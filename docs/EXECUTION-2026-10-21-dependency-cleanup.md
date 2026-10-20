# Active-tree dependency and language cleanup

Date: **2026-10-21**. Repository: `zlocorp/Portable-VirtualBox`;
working branch `dev/modernization-2026`. **No master merge, no release.**

## Scope and rationale

Remove 22 obsolete tracked assets from active `source`:
2 old AutoIt compiler EXEs, 5 old 7za/DevCon/SnetCfg EXEs,
14 outdated INI translations, and 1 retired SplashScreen.jpg.
Historical git commits still retain the bytes, while the quarantined
`source/legacy/Portable-VirtualBox.au3.disabled` is retained as a readable
reference and never included in the modern executable.

A stale root `build.bat` used to invoke in-repo AutoIt 3.3.16.1 and 7za.exe,
while a Windows CI audit required those binaries to exist. Both are replaced:
the batch entrypoint now forwards to the modern `scripts/build.ps1` with
an external signed AutoIt x64 compiler; CI checks retired assets are absent
and rejects any unexpected executable in the active `source` tree.
`BUILDING.md` documents actual build, tests and diagnostic-only ZIP packaging.
The historical binary audit (completed 2026-10-20) remains cited but no
longer runs against intentionally deleted files.

## Proof requirements

- Python static tree guard and negative fixture tests pass on Linux/Windows.
- Windows x64 compilation with official signed AutoIt **3.3.18.0** passes
  without old compilers/tools/translations/splash, including Unicode paths.
- Native AutoIt regression suite including RU/EN and readiness passes.
- Allowlisted 4-file diagnostic-preview ZIP has no obsolete/Oracle binaries.
- Disposable Windows-host native VM start/stop and verified exact-owned
  VBoxSup/VBoxSDS teardown still pass with pinned Oracle **7.2.22**.
- PR #7 remains Draft; historical master and user PCs remain untouched.

**Safety boundary:** this cleanup does not enable normal-user GUI VM
Start/Stop, Windows 11 standard-user/UAC, optional USB/network drivers or
a release. CI-only tests are research, not production privileged helpers.

## Verified result for the cleanup commit

[GitHub commit 430f2320](https://github.com/zlocorp/Portable-VirtualBox/commit/430f23202aad9c570443fd47c0144362121bfd40)
deleted **22** tracked obsolete `source/` assets (**4,528,609 bytes** total),
plus the old audit script, and replaced historical `build.bat` and
`BUILDING.md` with current x64 build instructions. A commit-bound tree read
proved no assets remain under `source/Aut2Exe` or `source/i_data`.
`source/legacy/Portable-VirtualBox.au3.disabled` and the original license
remain intact.

- [Python/static and x64 build CI 39502031096](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39502031096): **success**, 114 discovered Python tests on Linux and the source-tree absence guard; signed external AutoIt x64 compile, Cyrillic-path rebuild, initialized-profile preservation, and 4-file preview ZIP membership verified.
- [Native AutoIt 39502031102](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39502031102): **17 native test harnesses**, zero failures; RU/EN catalog and GUI text tests passed.
- [Oracle app64 verification 39502031092](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39502031092): **success** for pinned 7.2.22, no MSI/install effect.
- [Real disposable Windows native boot + exact-owned cleanup 39502023979](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39502023979): **success**, compiled AutoIt orchestrated the signed driver startup, empty VM boot and poweroff, independent verification, then VBoxSDS/VBoxSup resource teardown with clean final state.

**Acceptance:** Yes, proven tested preview/native CI workflows work without
any deleted legacy resource. **Not acceptance** for production GUI Start/Stop,
full guest OS, Windows 11 standard user, real USB relocation or recovery.

Additional ideas from forks/PRs are recorded separately in
[community review](REVIEW-2026-10-21-UPSTREAM-FORKS-PRS.md).

## Root compatibility build wrapper verified

[Final root build entrypoint CI 39503487607](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39503487607) succeeded:
the Windows `cmd.exe` step **called `build.bat` directly**, which
delegated to PowerShell and compiled the current x64 executable using
the signed externally obtained AutoIt toolchain. Static checks, full x64
compile, Cyrillic-path build, preview ZIP and unpacked first-run tests also
passed. No archived executable or `i_data` file was restored.
