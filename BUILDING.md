# Building Portable-VirtualBox (2026 development branch)

This describes the **active** `dev/modernization-2026` project. The historical
2010s batch/SFX build instructions have been retired.

## Requirements

- Windows x64 and the official **AutoIt 3.3.18.0** compiler, installed or
  extracted from [AutoIt](https://www.autoitscript.com/site/autoit/downloads/).
  The compiler root must contain `Aut2Exe/Aut2exe_x64.exe`.
- PowerShell 7 (preferred) or Windows PowerShell.
- Python 3 for non-native tests and packaging.
- No 7-Zip, DevCon, SnetCfg, Resource Hacker or historical bundled compiler.

## Build the current diagnostic preview

From the repository checkout:

```powershell
pwsh -NoProfile -File .\scripts\build.ps1 -AutoItRoot 'C:\Program Files (x86)\AutoIt3'
python -X utf8 -m unittest discover -s tests -v
pwsh -NoProfile -File .\scripts\test-native.ps1 -AutoItRoot 'C:\Program Files (x86)\AutoIt3'
python -X utf8 scripts/check_active_tree.py
```

Windows `build.bat` is a compatibility wrapper around
`scripts/build.ps1`. It no longer calls any in-repository compiler,
7za, or release/SFX packager.

Output: `build/Portable-VirtualBox_x64.exe` and `build/SHA256SUMS.txt`.
To create the **diagnostic-only** ZIP (not a usable hypervisor release):

```powershell
python -X utf8 scripts/package_preview.py --repo . --exe build/Portable-VirtualBox_x64.exe --out build/Portable-VirtualBox-diagnostic-preview.zip
```

The compiled GUI only provides read-only Windows diagnostics and user-owned
portable-folder preparation. Native VM execution and privileged VBoxSup/VBoxSDS
experiments are fenced to disposable GitHub Actions Windows hosts and are NOT
available as a supported normal-user start/stop workflow.

Oracle VirtualBox is not shipped in this repository or ZIP. The current
pinned signed Oracle 7.2.22 preparation and test instructions are in
[dependency inventory](docs/DEPENDENCIES-2026-10-20.md).

Old translations, splash artwork and executable tools were removed from the
active tree. Earlier versions remain recoverable in Git history. The old
launcher source remains deliberately disabled at
`source/legacy/Portable-VirtualBox.au3.disabled` for historical review.
Do not run it as a current launcher.

Original author credit and licensing: [LICENSE.md](LICENSE.md).

## Separate Manager-session experiment

`./scripts/build.ps1 -AutoItRoot <official-toolchain-root> -SessionExperiment`
builds `build/Portable-VirtualBox-Session-Test.exe` from its own entrypoint.
The ordinary build and six-member preview ZIP are unchanged. The experimental
EXE refuses an ordinary checkout/PC and needs the disposable hosted Windows
workflow plus its already-elevated effect adapter. These environment checks
are accident guards, not a security boundary or a production UAC helper.

The `manager-session.yml` workflow drives actual buttons and Oracle Manager,
verifies guest preservation/second-controller refusal and two exact-owned
cleanups. It publishes bounded evidence, not a runnable experimental package.
See [the execution report](docs/EXECUTION-2026-10-21-manager-session.md).
