# Large-batch delivery: functional Portable-VirtualBox alpha

Date: 2026-10-20. User explicitly requests **large integrated functional packages**, not a series of tiny unrelated steps. This plan governs the next development work. Clean original `vboxme/Portable-VirtualBox` is the only upstream base; do not use historical `zlocorp` changes. Maintain existing draft PR #7 against `work/upstream-baseline-2026`; no master merge, release or user-PC testing.

## Current evidence to preserve

- Signed Oracle VirtualBox **7.2.22** MSI/CAB → signed/hashes-verified 185-file app64 (247834716 bytes); earlier 7.2.20 proofs remain historical.
- One complete disposable-host blank VM boot/poweroff + signed VBoxSup/VBoxSDS teardown; two consecutive cycles preserved original VM UUID.
- Complete-root Unicode relocation and same-VHD P:→Q: letter reassignment both verified.
- Compiled AutoIt 3.3.18.0 preview with RU/EN diagnostics GUI, profile creation/inspection.
- `source/PortableCISession.au3` already performs a **real AutoIt→Oracle CLI→VBoxSDS registration/cleanup** on disposable hosted Windows ([native session success run 39438429411](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39438429411)). It is deliberately CI-gated and still cannot start VMs or manage VBoxSup.
- Previous old code in `source/legacy/Portable-VirtualBox.au3.disabled` is never compiled.

## Batch A implementation checkpoint: compiled native VM engine

At code/test commit `539a7542787ca24195d6f1921ec9ffe3a1728a20`, the compiled AutoIt entrypoint has a new **hidden CI-only native VM session**. On an isolated Windows Server 2022 runner, it creates an empty VM, verifies UUID and state, starts it via real VBoxManage, powers it off and verifies the result. Host-side independent verification and the already-audited signed VBoxSup/VBoxSDS cleanup complete the session with zero remaining services. [Evidence](../EXECUTION-2026-10-20-native-autoit-boot.md) / [successful run](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39450334031).

**Still open for Batch A:** production-safe elevated driver helper, Start/Stop controls for the Oracle Manager GUI, ordinary-user Windows 11 approval, existing-VBox coexistence/refusal and robust failure/reboot/owner recovery. CI-only environment markers are **not** a security boundary and do not authorize distribution or local execution. Do not mark Batch A complete merely because the experimental headless VM starts.

## Batch A checkpoint: integrated compiled executable (2026-10-20)

[Commit 79a5991b](https://github.com/zlocorp/Portable-VirtualBox/commit/79a5991b091e0b76b308a85486d67a8d313791d9) moved the ordering of signed driver staging/start, real AutoIt native blank-VM boot/poweroff, independent host verification and exact-owned SDS/SUP cleanup **into the compiled AutoIt entrypoint**. [Windows integrated CI 39494324031](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39494324031) passed; [native CI 39494330200](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39494330200) passed 16 harnesses, zero failures; [core x64 CI 39494330205](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39494330205) passed. [Evidence](../EXECUTION-2026-10-20-integrated-native-lifecycle.md).

The signed-driver *effects* are still research PowerShell scripts running as an elevated disposable CI runner. They are **not** a reviewed production helper. Normal RU/EN UI/Manager Start/Stop, UAC/standard-user Windows 11 tests, safe recovery and coexistence remain blocked. **Batch A is not complete.**

## RU/EN + Oracle 7.2.22 refresh (2026-10-20)

- GUI switches both language and the previously requested readiness result; refreshed diagnostics and Windows observation/product types display in RU/EN. Long paths and missing app64 status no longer silently mislead.
- [Native test run](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39497271846): 17 AutoIt harnesses, no errors; i18n has 157 assertions, GUI text has 10.
- Current pinned Oracle **7.2.22** official distribution and new exact VBoxSup SYS/INF/CAT hashes: [passive 185-file package verification](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39497891196), [compiled AutoIt native boot/teardown](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39498269366), both verified on disposable Windows Server 2022. No claim of standard-user Windows 11.
- AutoIt **3.3.18.0** remains current. Legacy 7za/DevCon/SnetCfg stay quarantined and outside the runtime.

## Batch A: usable launcher core, one substantial change set

Deliver, together:
1. A real first-run main window with RU/EN selector, portable app/profile paths, state/preflight and Start/Stop actions. No inert enabled buttons. Preserve current read-only CLI diagnostics and honest default-disabled runtime until safe activation is implemented.
2. Separate non-elevated frontend from minimal privileged system helper; execute only specific trusted driver and VBoxSDS operations. Reuse verified signed/package/identity rules, with exact evidence for every operation, bounded waits, and no arbitrary process-name termination.
3. Start Oracle Manager under `VBOX_USER_HOME`, default machinefolder inside `data/Machines`, optional built-in `setproperty language ru`. Wait for all owned VirtualBox activity and refuse cleanup while any VM/shared process remains. Preserve user VM data.
4. Safe partial-failure and reentrancy handling with a plain diagnostic log/export; user sees error and recovery steps, no destructive guessing.
5. Compile and exercise end-to-end on **isolated Windows 11 x64** (hosted Windows Server 2022 may support native tests but is not Windows 11 acceptance). Run clean host + existing system VBox refusal and verify no alien service/VM mutations.

Exit criteria: launch → run an empty VM → poweroff → close manager → clean only owned driver/service registrations → reopen same VM UUID. All required steps actually called from the new compiled AutoIt launcher, not merely parallel PowerShell experiments. Until this passes, no alpha is labeled usable.

## Batch B: complete portable profile and practical UX

- First-run setup flow, remembered options inside `data/`, structured status; user-chosen VM folder; profiles survive Unicode/spaces and drive-letter change. Read-only migration preview and backup before explicit consent.
- Inspect snapshots/differencing media; do not assume a simple .vbox and one VDI is a complete VM.
- RU/EN entire launcher, no 2010-era broken strings; Oracle UI language through its own setting. Settings, About, diagnostics and safe log copying. Visual UI testing on interactive Windows.
- Run two actual sessions with the same nonempty test disk and post-cleanup verification.

Exit criteria: ordinary user can launch/stop confidently and understand any block; VM data is preserved.

## Batch C: updates and package for testing

- Update checks for Oracle stable versions and launcher separately, download only pinned official HTTPS assets and verify release metadata + Authenticode, never blindly execute downloads.
- Stage a new `app64` side-by-side while no VM runs, then atomic/refusal-safe publication, retained previous version and explicit rollback. Do not touch data/ VMs.
- Review and exclude stale legacy `7za` (16.04), DevCon (Win7), Snetcfg (Server 2003) and old AutoIt 3.3.16.1 from runtime ZIP; use modern signed official compiler and PnP/Windows APIs. Preserve license/author notice.
- Publish a **prerelease ZIP only after** runtime/GUI/Windows11 acceptance and clear redistribution review. No Extension Pack, optional USB or bridged drivers by default.

Exit criteria: isolated guest OS test, crash/cancel/restart/drive-relocation/coexistence cases, signed/hash-documented package and manually approved release.

## External PR/fork findings captured for acceptance (2026-10-21)

[Reviewed upstream PRs, recent forks and concrete user failures](../REVIEW-2026-10-21-UPSTREAM-FORKS-PRS.md). Their **test scenarios**, not their unsafe legacy runtime code, are relevant:
- **Batch A:** keep Manager and VM process lifetimes distinct; wait for owned `VirtualBoxVM`/`VBoxHeadless` activity and refuse teardown on uncertain/shared processes, stale `VBoxSDS` registration or unexpected session exit. Do not use blanket admin elevation, global name-based process kills or bare `sc` cleanup.
- **Batch B:** a moved root with old paths or missing `Machines` directory must produce non-destructive, actionable recovery; test Unicode paths, existing UUID, snapshots/medium chains and repeated starts.
- **Batch C:** interrupted downloads, unsuccessful extraction and failed update must never delete the launcher or user VMs. Optional VirtualBox 7.x icon refresh is lower priority.

## Work rhythm

- One integrated user-visible feature package per iteration, ideally spanning frontend + backend + native test + CI + docs.
- Commit work-in-progress within `dev/modernization-2026`; run red→green tests for changed behavior. Do not declare a batch complete based solely on a static Python contract or mock.
- Preserve draft PR #7 as integration/research record. Once Batch A passes, split stable changes from clean upstream into thematic smaller review PRs before any mainline merge.
- Avoid rewriting already proven low-level infrastructure unless a specific acceptance test reveals a flaw.

**Current immediate move:** implement Batch A, rather than adding another speculative design-only subsystem.
