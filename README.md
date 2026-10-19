# Portable-VirtualBox (modernization branch)

> **Development preview, not a functional portable hypervisor.** VM startup, driver installation and service cleanup remain disabled. Do not distribute this executable as a usable VirtualBox release.

Based on the original `vboxme/Portable-VirtualBox` master snapshot `5b58dbbe701c3e2eb348942a9059708063b0cb96`. Historical personal modifications are not merged; the old fork remains in `archive/legacy-zlocorp-2020`. Work is isolated in `dev/modernization-2026`; draft [PR #7](https://github.com/zlocorp/Portable-VirtualBox/pull/7) targets the clean upstream reference, not historical master.

## Verified development capabilities

- Windows x64 compilation with the official signed AutoIt 3.3.18.0 compiler, including checkout paths with spaces and Cyrillic characters.
- **Native read-only Windows observations:** SCM service configuration/status, process identity through retained query handles, installation keys in both registry views, and workstation/server product type. Unknown/denied observations block preflight instead of becoming false absence. Querying a resource never grants ownership or permission to mutate it.
- Exact-version Oracle download verification and passive PE resource extraction into MSI/CAB files.
- **MSI/CAB to new app64 file preparation:** the pinned Oracle 7.2.20 package produces 185 application files / 247738522 bytes without running its installer, MSI actions or any payload. Read-only MSI tables determine placement; cabinet callbacks use Unicode-aware file I/O. Per-file hashes, key AMD64 headers, signatures and unchanged inputs are checked in CI.
- Native AutoIt lifecycle policy and exclusive journal snapshots. This is tested policy code, not a completed privileged Windows service adapter.
- Read-only VM registry inventory and regression tests for malformed input, download races, staging publication, XML encodings and Windows paths.

The old runtime is preserved byte-for-byte as `source/legacy/Portable-VirtualBox.au3.disabled` and is not compiled. The preview does not request administrator rights or start virtual machines. Hosted test results do not establish coverage under a standard-user Windows account.

## Commands

```text
Portable-VirtualBox_x64.exe --version
Portable-VirtualBox_x64.exe --selftest
Portable-VirtualBox_x64.exe --diagnose
Portable-VirtualBox_x64.exe --preflight
```

Diagnostics print status/counts without private image paths or service account names. An unknown observation returns diagnostic exit 4. A blocked preflight returns 3. A clear preflight is neither ownership evidence nor authorization to run an unverified runtime. With no arguments the preview shows a warning and exits.

Developer tools:

```powershell
./scripts/build.ps1 -AutoItRoot 'C:\Program Files (x86)\AutoIt3'
./scripts/test-native.ps1 -AutoItRoot 'C:\Program Files (x86)\AutoIt3'
python -X utf8 -m unittest discover -s tests -v
python scripts/audit_source.py --enforce
python scripts/oracle_release.py 7.2.20
python scripts/vm_inventory.py 'C:\Portable-VirtualBox\data\.VirtualBox\VirtualBox.xml'
```

`python scripts/prepare_app64.py --help` describes the Windows developer preparation interface. It requires a trusted expected wrapper checksum and publisher-signature validation by its caller; the hosted workflow performs those checks. The output directory must not already exist. This tool prepares files, not system prerequisites, COM registration or drivers, and is not yet integrated into the AutoIt UI.

VM inventory hides UUIDs and paths unless `--details` is requested. It does not migrate data.

## Status and evidence

See the [Windows observation report](docs/EXECUTION-2026-10-19-observation.md), [app64 preparation report](docs/EXECUTION-2026-10-19-app64.md), [observation implementation plan](docs/plans/2026-10-19-windows-observation.md), [broader roadmap](docs/MODERNIZATION-2026.md), and [security model](docs/SECURITY-MODEL.md).

At verified checkpoint `d6f2137` the Python suite contains 59 tests: Windows passes 58 and skips one symbolic-link test; Linux passes 54 and skips five Windows-native tests. The compiled native suite passes 164 assertions: 56 lifecycle, 11 runtime, 77 Windows observation and 20 edge checks. The Oracle/app64 preparation also passes. None of this establishes Windows 11 driver/VM compatibility or bit-for-bit reproducible AutoIt binaries.

## Attribution and release boundaries

Preserve the original launcher credit to Michael Meyer and contributors and the original license in `LICENSE.md`. This branch does not silently relicense upstream. Deac2 and bitamind were research references, not wholesale imported code. Oracle payloads and Extension Packs are not published as CI artifacts or project releases. Existing upstream BUILDING.md describes historical packaging and is not the current CI procedure.

Next work is journal/observation coordination with synthetic effects, followed by separately reviewed system-changing adapters, dependency/COM checks and isolated VM acceptance. Neither a master merge nor a release has been performed.
