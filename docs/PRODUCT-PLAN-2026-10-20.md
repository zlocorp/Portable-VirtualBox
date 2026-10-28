# Portable-VirtualBox: product implementation roadmap

Date: 2026-10-20. Target: Windows 11 x64, Oracle VirtualBox 7.2.x.
Working branch: `dev/modernization-2026`; [Draft PR #7](https://github.com/zlocorp/Portable-VirtualBox/pull/7). No merge into historical `master` and no release until explicit acceptance.

## Principle: product first, research only where it unblocks a feature

Users need a small trusted launcher with **Start**, **Stop**, **Settings**, **Update**, **Diagnostics**, native Russian/English, and portable `app64` plus VM data. The existing backend experiments are not a usable product. Stop adding generic orchestration unless a real production operation demonstrably requires it.

### Verified research (native integration remains CI-only)

- Signed Oracle 7.2.22 wrapper -> MSI/CAB -> 185 complete app64 files (247834716 bytes), version/hashes/signatures; earlier 7.2.20 evidence remains historical.
- VBoxManage CLI, isolated VBOX_USER_HOME, machinefolder, registration of a new test VM.
- Signed VBoxSup staging/activation, empty VM boot/poweroff, exact-owned VBoxSDS/VBoxSup cleanup.
- Two successive VM sessions with same UUID/VM config and clean service teardown.
- Root relocation between Unicode paths and P: -> Q: on one private VHDX, with unchanged UUID/VDI hash.
- AutoIt 3.3.18.0 build, host preflight/diagnostics, tested journal policies and native read-only Windows probes.

**NOT VERIFIED:** booting a guest OS with disk, snapshots and differencing media, installed VirtualBox coexistence, actual Windows 11 x64 standard-user privilege transitions, cross-machine USB portability, crash/interrupted state and robust rollback. Existing development CLI is not a runtime launcher.

## P0: useful product-facing changes in development now

- [x] Confirm official VirtualBox 7.2.22 (20 October 2026) and AutoIt 3.3.18.0 are the current stable versions as of this date.
- [x] Audit inherited 7za/DevCon/SnetCfg/compiler EXEs by version, SHA-256 and Authenticode without execution. Keep them quarantined. Never ship them merely because they were in upstream.
- [x] Introduce an RU/EN catalog for the **launcher**, with automatic Russian host locale, explicit locale switch, native key coverage, and documented CLI help.
- [x] Add a real *read-only* GUI: status panel, RU/EN language radio buttons, refresh, copy diagnostic report, close. No fake Start button.
- [x] Validate UTF-8 Russian CLI output on a compiled hosted Windows build (actual Cyrillic byte content; first failing test reproduced AutoIt's ANSI stdout issue, then passed after fix). Native catalog coverage: 97 assertions.
- [ ] Visually inspect GUI controls and layout on an isolated interactive Windows 11 desktop; compilation alone cannot validate accessibility or text clipping.
- [x] Confirm `VBoxManage setproperty language ru` exits zero under a private portable `VBOX_USER_HOME` on disposable Windows ([CI run 39427583563](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39427583563)). This configures Oracle's supported language preference; visual Manager translation remains unverified.
- [ ] Choose a user-visible launcher version independently of Oracle's runtime version.

## Larger implementation batches, not individual helper releases

**Authoritative scope:** [large-batch delivery plan](plans/2026-10-20-large-batch-delivery.md). Earlier diagnostic-only A / production B labels are superseded: **Batch A includes the complete functional Start/Stop launcher.**

### Batch A: safe actual Start/Stop and Manager lifecycle (IN PROGRESS)

Foundations: corrected RU/EN profile/readiness GUI, signed Oracle 7.2.22 app64 and compiled AutoIt blank-VM engine. The earlier CI 39494324031 used 7.2.20; [new 7.2.22 native boot-and-teardown CI 39498269366](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39498269366) passed. As of [CI 39494324031](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39494324031), the **compiled EXE** orchestrates driver stage/start, native VM boot/poweroff, independent host verification and exact-owned VBoxSDS/VBoxSup teardown. All privileged effects still execute through CI-only research PowerShell scripts on an already-elevated disposable Windows Server 2022 runner. [Execution details](EXECUTION-2026-10-20-integrated-native-lifecycle.md).

Remaining **Batch A** exit gates: narrowly scoped privilege-separated helper/UAC, exact session ownership and failure recovery, normal RU/EN GUI start/stop of Oracle Manager, coexistence refusal and a two-cycle same-UUID test on **isolated Windows 11 x64** as a standard user. Regular UI correctly remains `RUNTIME_DISABLED`.

### Batch B: practical portable-profile UX (NOT STARTED)

User-configurable paths, safe data migration and backup, snapshot/differencing-media awareness, complete RU/EN user settings/diagnostics, and interactive GUI accessibility/Unicode-path acceptance.

### Batch C: trusted updater and release candidate (NOT STARTED)

Signed Oracle/launcher update staging and rollback, allowlisted ZIP with provenance/licensing, and manual prerelease approval after functional Windows 11 testing. Optional USB/bridged networking deferred.

## P1: minimum usable launcher (first *functional* development milestone)

1. **App layout and first-run setup:** **partly DONE** for automatic, local, non-destructive `data/.VirtualBox/`, `data/Machines/`, `logs/` provisioning in the actual EXE and GUI; path safety, Unicode and repeat-preservation tested. `app64` remains a separately provisioned Oracle tree. User-selected paths, migration backups and USB removal safety remain to implement.
2. **Actual safe startup:** user sees check results first. Detect existing system Oracle installation and running VBox VMs; fail closed for conflicts. Read and verify exact driver files. Request elevation **only** for required system changes. Use a reviewed, per-session operation record and only exact system actions tested on the disposable host. Show progress/error instead of silently mutating.
3. **One-click start/stop:** start Oracle VirtualBox Manager with this portable profile; permit VM startup. Close normally and only clean resources created/owned by this session after all relevant VBox VMs/processes exit. Never force-kill another user's VM or remove globally matching services.
4. **Resilience:** launch twice, cancel halfway, missing admin privileges, hash mismatch, busy service, changed service identity, unplug/no media, retry/refusal, crash/restart. Cleanup must preserve VDI/VBOX/snapshots, and incomplete cleanup must be clearly reported.
5. **Working GUI:** buttons `Запустить VirtualBox`, `Остановить/Закрыть`, `Настройки`, `Обновления`, `Диагностика`, `О программе`. Every enabled button has a real action. Localization is RU/EN end-to-end; do not present disabled experimental functionality as finished.

**P1 acceptance:** first-run->launch->empty VM boot->poweroff->shutdown->verified zero newly owned VBox resources on isolated Windows 11 x64; same VM and UUID on repeat. Pre-existing Oracle installation is never altered. No historical master merge yet.

## P2: quality-of-life and language

- User-controlled default folders; portable paths survive full-root relocation. Never rewrite arbitrary VirtualBox.xml with string replace, never delete backups, never automatically unregister VMs.
- Explicit optional migration with read-only preview of UUID, medium chains/snapshots, backup and rollback before consent.
- **Two distinct locales:** new AutoIt launcher RU/EN; Oracle VirtualBox Manager language set via its own built-in preferences/`VBoxManage setproperty language ru` under the portable `VBOX_USER_HOME`. GUI language choice must not unexpectedly change a pre-existing system profile.
- Proper Russian text review, code pages/UTF-8, Cyrillic paths; no broken legacy 2010-era translation. Keep original 14 INI files archived until individually reviewed; do not claim 14 modern languages.
- Privacy-preserving diagnostics and understandable errors, log export, no sensitive full paths in default report.

## P3: update/install experience

- **Manual Check for updates**, compare exact Oracle stable release only; don't silently download/install a new version.
- Verify official HTTPS manifest SHA-256, installer Authenticode and internal MSI/CAB composition. Stage a *new* app64 side by side. Never swap while VM or VBox processes are running; preserve data, old verified build, recovery status and optional rollback.
- Separate launcher updates from Oracle updates. Do not silently install Oracle Extension Packs or change existing VM data.
- License/provenance audit before redistribution; ZIP-first packaging and per-release checksums. No inherited unsigned executables in the package by default.

## P4: optional components / after MVP

- USB passthrough, bridged/host-only networking and extra drivers are OFF by default; enable only with tested driver-specific install/cleanup and accurate safety prompts. NAT can be part of basic VM functionality.
- Extension Pack is opt-in with explicit Oracle licensing; not automatically bundled.
- Beyond-Windows-11/x64, x86/ARM64, legacy Windows, automatic app SFX and 12+ legacy translations are separate compatibility work.

## P5: release acceptance and GitHub strategy

- Keep dev branch + Draft PR #7 as *research/reference*, NOT one giant unreviewed PR into historical master.
- Once the minimal launcher is genuinely functional, start a clean integration branch from pinned `vboxme/master` and bring in vetted modules as thematic PRs: core/packaging, driver lifecycle, portable profiles, RU/EN UX, updater. Preserve original author/license notices.
- Publish prerelease ZIP only after isolated Windows 11 E2E tests (ideally boot small Linux guest from test disk), driver cleanup, coexistence refusal, path changes, failure/rollback and GUI review.
- `master` remains unchanged until an explicit migration/default-branch decision; legacy archive retained.

## Order of next concrete work

1. Finish **Batch A**, replacing runner-only system-effect adapters with a reviewed minimal elevated helper and real RU/EN GUI Oracle Manager Start/Stop. Never use environment markers as a security boundary.
2. Test standard-user/UAC and coexistence/refusal on an isolated Windows 11 x64 host. Windows Server 2022 CI is not Windows 11 acceptance.
3. Complete **Batch B** portable-data UX and **Batch C** verified update/release only after functional acceptance.
4. Preserve Draft PR #7 and the historical master; prepare smaller reviewable integration PRs before any merge.
