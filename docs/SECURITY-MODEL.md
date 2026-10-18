# Runtime safety model and review gates

**Status:** development design, not yet implemented as a complete Windows runtime.
**Scope:** independent Windows 11 x64 host, modern VirtualBox 7.2.x target; no warranty of compatibility until functional testing.

## Threats in the inherited upstream code

The upstream launcher at `5b58dbbe` contains potentially hazardous operations:

1. `taskkill /im msiexec.exe /f` is not scoped to its own installer process.
2. Global `ProcessClose("VBoxSVC.exe")` and `ProcessClose("VBoxSDS.exe")` have no process-ownership proof.
3. System directory DLL/driver `FileCopy` / `FileDelete` can interfere with installed software and OS components.
4. `sc create/start/stop/delete VBox*` is performed without a transaction log and robust service ownership verification.
5. COM registration/unregistration and the VBoxSDS service may affect an existing installation.
6. Direct string edits of `VirtualBox.xml`, deletion of `VirtualBox.xml-prev` and other files risk user data loss.
7. The legacy downloader/updater has hard-coded old HTTP endpoints and unverified installers.
8. First-run elevation through `#RequireAdmin` grants privileges before the user sees what changes will occur.

The source auditor reports exact lines: `python scripts/audit_source.py`. Reports are not runtime vulnerability exploits or proof of damage.

## Current barrier

A development gate is executed **before** inherited runtime statements. The original `#RequireAdmin` directive is inactive in the development branch; read-only `--diagnose`, `--preflight`, and pure `--selftest` exist for CI. Running without a recognized command does not reach legacy driver/service and installer code. **Do not remove the gate until the requirements below are fully satisfied.**

## Required runtime contract (future implementation)

- Preflight before privilege escalation: Windows build and CPU architecture, binary identity/version, existing host installation, running VM processes, registered services, source/destination paths, disk space, required drivers and signing checks.
- Fail closed when another VirtualBox installation, VM process or unowned component could be affected. Hybrid mode is separate and opt-in.
- Service driver operations: record exact pre-run state, executable/driver image path, creation exit status and service configuration. A service may be stopped or deleted only when ownership of a newly created resource has been verified and is still valid at cleanup time.
- Do **not** delete DLLs from system directories or kill every process with a matching name. Use dependency-specific prerequisites and recorded PIDs.
- Never delete `VirtualBox.xml-prev`, `VirtualBox.xml-tmp`, VM `*.log`, VDI/VMDK/VBOX/snapshot data automatically in the startup path.
- Keep user VM registries untouched without an explicitly authorized migration. Prefer official VBoxManage operations; stage a backup and rollback before any migration.
- Record each privileged action and result in local logs. On partial failure preserve evidence and user data; do not claim a successful cleanup unless verified.
- Oracle downloads: HTTPS, exact version, trusted SHA-256 manifest and checksum validation before any installation. Check Authenticode/signing and legal requirements in a separate gate.
- Extension Packs are optional, **not** silently bundled, downloaded or installed.
- Every release needs Windows 11 x64 acceptance on a disposable isolated test environment, including first run, multiple runs, intentional failure, shutdown, existing host VBox coexistence and relocated VM path.

## What tests currently cover

Automated CI covers (1) static risk pattern detection, (2) side-effect-free AutoIt helper checks, (3) developer gate execution, (4) read-only Windows inventory, (5) validated checksum selection and atomic non-overwriting downloads, (6) x64 compilation, compiler signature and PE output checks.

Automated CI does **not** validate successful VM execution, kernel driver installation, service cleanup, Host-only/Bridged networking, USB, snapshots, VM migration, code signing of downloaded Oracle installations, or release readiness. Any claims about these features require separate evidence.

## Review discipline

- Never merge a code change to `master` or publish a release automatically from this branch.
- Use multiple small PRs when high-risk subsystem changes can be separated.
- Commit the exact toolchain version, source SHA and acceptance evidence.
- Treat vulnerabilities in referenced forks as findings to investigate, not as vetted fixes.
