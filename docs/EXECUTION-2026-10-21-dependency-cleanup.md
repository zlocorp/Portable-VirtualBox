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
