# Portable-VirtualBox (modernization branch)

> **Development preview only.** This branch is NOT a functional replacement for VirtualBox and MUST NOT be distributed as a ready-to-use portable virtualization product.

This code base starts from the original [vboxme/Portable-VirtualBox](https://github.com/vboxme/Portable-VirtualBox) `master` snapshot at commit `5b58dbbe701c3e2eb348942a9059708063b0cb96`. Historical personal modifications are **not merged**. The preserved old fork is available in the `archive/legacy-zlocorp-2020` branch.

## Current scope

- Build an x64 AutoIt executable with the official signed AutoIt 3.3.18.0 compiler on GitHub Actions.
- Run a **read-only** host diagnostic and pure-policy self-tests without elevation.
- Keep the inherited 2013–2024 runtime explicitly disabled while driver, service, VM and installer lifecycle code is reworked.
- Provide an independent Oracle installer **metadata / checksum verifier**. It does not execute packages.
- Target Windows 11 x64 and VirtualBox 7.2.x for future compatibility verification. **Neither runtime support nor driver compatibility has been established.**

### Preview executable commands

```text
Portable-VirtualBox_x64.exe --version
Portable-VirtualBox_x64.exe --selftest
Portable-VirtualBox_x64.exe --diagnose
Portable-VirtualBox_x64.exe --preflight
```

`--preflight` performs **read-only** checks of Windows build/architecture, portable VBox executable presence and version, existing Oracle installation, common VBox services and running processes. No preflight result authorizes unsafe execution. Running the preview without arguments shows a warning and exits; it never launches a VM.

### Build and tests

GitHub Actions workflow: [Portable-VirtualBox CI](.github/workflows/ci.yml). The `compile` job downloads the official portable AutoIt 3.3.18.0 toolkit, verifies the compiler's Authenticode signature, builds x64, checks the PE output and uploads an **unverified-runtime** artifact and SHA-256. No release is published and no VirtualBox drivers, services or installers are run.

For a local developer workstation with the official AutoIt installation:

```powershell
./scripts/build.ps1 -AutoItRoot 'C:\Program Files (x86)\AutoIt3'
python -m unittest discover -s tests -v
python scripts/audit_source.py
python scripts/oracle_release.py 7.2.20
# Optional: download only, never execute:
python scripts/oracle_release.py 7.2.20 --download .\VirtualBox-official.exe
```

The downloader requires an existing output directory, refuses to overwrite existing files and accepts only a specific version and a manifest-verified Windows installer filename.

## Implementation plan and risks

- [Modernization work packages](docs/MODERNIZATION-2026.md)
- [Host and VM safety rules](docs/SECURITY-MODEL.md)
- Original upstream build instructions (legacy, not applicable to the new development CI): [BUILDING.md](BUILDING.md)

**Important:** This is a portable launcher project. It cannot make Oracle VirtualBox kernel drivers magically portable or remove all requirements for privileged operations on Windows. Never run experimental launchers against the only copy of valuable VM disks or snapshots.

## Upstream, third-party forks, licensing

The original launcher credits Michael Meyer and contributors. Preserve the original license and attribution; this branch does not silently relicense upstream. Any use of third-party fork code and the redistribution of Oracle VirtualBox binaries, Oracle Extension Packs or bundled tools require independent license and provenance review.

The [Deac2](https://github.com/Deac2/Portable-VirtualBox) and [bitamind](https://github.com/bitamind/Portable-VirtualBox) projects are research references, not automatically imported code.
