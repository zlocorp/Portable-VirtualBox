# Portable-VirtualBox (modernization branch)

> **Development preview, not a functional portable hypervisor.** VM startup, driver installation and service cleanup remain disabled. Do not distribute this executable as a usable VirtualBox release.

Based on the original `vboxme/Portable-VirtualBox` master snapshot `5b58dbbe701c3e2eb348942a9059708063b0cb96`. Historical personal modifications are not merged; the old fork remains in `archive/legacy-zlocorp-2020`. Work is isolated in `dev/modernization-2026`; draft [PR #7](https://github.com/zlocorp/Portable-VirtualBox/pull/7) targets the clean upstream reference, not historical master.

## Verified development capabilities

- Windows x64 compilation with the official signed AutoIt 3.3.18.0 compiler, including checkout paths with spaces and Cyrillic characters.
- Read-only host diagnostics and preflight. Existing VBox installation, services and processes are review blockers, not resources we may delete.
- Exact-version Oracle download verification, passive PE resource extraction into MSI/CAB files, and read-only MSI metadata inspection. No Oracle installer, MSI installation or VBox driver is executed by this preparation workflow.
- Native AutoIt lifecycle policy and exclusive journal snapshots. This is tested policy code, not a completed privileged Windows service adapter.
- Read-only VM registry inventory and regression tests for download races, malformed input, XML encodings and Windows paths.

The old runtime has been physically removed from the compiled entrypoint and preserved byte-for-byte as `source/legacy/Portable-VirtualBox.au3.disabled`. It is not included in the build. The preview entrypoint does not request administrator rights or start virtual machines.

## Commands

```text
Portable-VirtualBox_x64.exe --version
Portable-VirtualBox_x64.exe --selftest
Portable-VirtualBox_x64.exe --diagnose
Portable-VirtualBox_x64.exe --preflight
```

A clear preflight is not authorization to run an unverified runtime. With no arguments the preview shows a warning and exits.

Developer tools:

```powershell
./scripts/build.ps1 -AutoItRoot 'C:\Program Files (x86)\AutoIt3'
./scripts/test-native.ps1 -AutoItRoot 'C:\Program Files (x86)\AutoIt3'
python -X utf8 -m unittest discover -s tests -v
python scripts/audit_source.py --enforce
python scripts/oracle_release.py 7.2.20
python scripts/vm_inventory.py 'C:\Portable-VirtualBox\data\.VirtualBox\VirtualBox.xml'
```

VM inventory hides UUIDs and paths unless `--details` is requested. It does not migrate data. Package extraction is a developer preparation step, not an unpacked `app64` tree or a working VM launcher.

## Status and evidence

See the [execution report](docs/EXECUTION-2026-10-19.md), [completed iteration and next tasks](docs/plans/2026-10-18-preparation-and-lifecycle.md), [broader roadmap](docs/MODERNIZATION-2026.md), and [security model](docs/SECURITY-MODEL.md).

At executable-code commit `d83e6ff`, 35 Python tests and 67 native AutoIt assertions passed; hosted Windows preparation verified the actual Oracle 7.2.20 wrapper and extracted packages. These checks do not establish Windows 11 driver/VM compatibility or bit-for-bit reproducible binaries.

## Attribution and release boundaries

Preserve the original launcher credit to Michael Meyer and contributors and the original license in `LICENSE.md`. This branch does not silently relicense upstream. Deac2 and bitamind were research references, not wholesale imported code. Oracle payloads and Extension Packs are not published as CI artifacts or project releases. Existing upstream BUILDING.md describes historical packaging and is not the current CI procedure.

Further work requires MSI/CAB file staging, real Windows service/process adapters, explicit migration and isolated VM acceptance. Neither a master merge nor a release has been performed.
