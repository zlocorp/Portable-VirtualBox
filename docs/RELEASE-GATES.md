# Minimal Russian one-VM release gates

Reviewed 2026-11-11; exact verification checkpoints are recorded below. **Not release-approved.** The goal is a usable Russian launcher for one powered-off/local VM with its snapshot chain, without broadening system privileges or recovery scope. The ordinary diagnostic preview remains separate from a runnable candidate. See [security boundaries](SECURITY-MODEL.md) and the [isolated ALPHA procedure](ALPHA-WINDOWS-TEST.md).

**Never run the system-effect acceptance below on the primary OS or valuable VMs.** Use disposable isolated Windows hosts with recoverable snapshots and disposable guest data. Do not disable UAC, antivirus, SmartScreen or HVCI to make a test pass. Unsupported host/security configurations must be reported or refused, not silently worked around.

## Evidence available, not a workstation sign-off

- **Read-only observer checkpoint `157a615`: seven triggered workflows passed**, including [Windows file-only preparation/reconciliation](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/42982570559) and [native contracts](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/42982577245). Windows ran 291 Python tests (2 platform/privilege skips); the genuine 185-file pinned Oracle inventory was inspected as intact, partially removed and absent on disposable copies, with original hashes unchanged. This is observational evidence only, never cleanup/resume authority.
- **Runnable boundary checkpoint `576da6b`:** [fixed helper with medium-token Alpine disk I/O and exact-owned cleanup](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/42981522499), [guarded interrupted preparation](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/42981522504) and [noninteractive UAC pending](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/42981522496) passed. Later observer fixes changed no privileged/runtime source. These hosted checks do not prove interactive workstation UAC. [Exact-owned orphan recovery](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/42981522492) passed on attempt 2 at that same code checkpoint; attempt 1 stopped before its live-guest/recovery checks with Oracle `VERR_NEM_VM_CREATE_FAILED`. Preserve both outcomes rather than treating the first as accepted.
- **11 workflow runs passed for `a98d0f0`**, including [build](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/42974034394), [native policies](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/42974034486), [fixed helper](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/42974026590) and [interrupted recovery](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/42974026974). This is an exact-checkpoint CI result, not a claim that every workflow ran or that later edits passed. Before promotion, retain the actual run URLs, head SHA, artifacts and conclusions for the final candidate; a green branch badge is insufficient.
- Actual compiled launcher/Oracle/Alpine boot, guest VDI sector readback after two driver sessions and snapshot preservation: [run 40407596523](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40407596523).
- Four powered-off directory/drive-letter relocation cases with UUID and disk-hash preservation: [run 40462477639](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40462477639).
- RU/EN/RU launcher and actual Russian first Oracle start/reopen plus English second start, including inspected screenshots: [launcher 41537264954](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/41537264954), [Oracle 41537257180](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/41537257180).
- Fixed-action helper, protected ownership receipts, durable attempt journals, one-shot recovery and independently verified ALPHA packaging exist in the source. These are implemented safeguards, not evidence of arbitrary power-loss recovery or interactive UAC acceptance.

The linked historical runs establish only their own tested checkpoints. Re-run affected checks on the candidate; do not copy an old pass into a new release record.

## Known blocking findings

- **Cleanup/recovery is not generally retryable after operational failure.** One-shot proof/cleanup directories can block a second attempt even after a refusal before deletion. The new payload-only continuation below addresses a narrower case after a durable teardown checkpoint; it does not make system-effect cleanup generally retryable. A transient error may therefore leave retained resources without supported retry completion. Fail-closed retention is not successful rollback. This remains an everyday-release blocker until separately fixed and tested; do not remove receipts/directories or broaden cleanup to bypass it. UAC denial before helper execution is a separate, retryable consent case.
- The locale-dependent published-INF parser and continuation after failed/unknown driver start have source fixes and file-only behavioral regressions. A narrow `StartFailedStopped` recovery path retains all original ownership checks and rechecks stopped SCM/WMI state before removing the exact package. **These are not workstation sign-off:** require final-candidate Windows PowerShell 5.1, real driver lifecycle and isolated workstation results. Timeout/unknown start results remain blocked rather than granted cleanup authority.

## Gates before promoting a runnable candidate

- [ ] **Finish before changing builds.** Old active/incomplete sessions must be finished or recovered using their original paired frontend/helper. New published-INF receipt fields and the embedded script inventory intentionally reject old unfinished sessions. Never infer replacement ownership or remove old protected receipts to make an upgrade pass.
- [ ] **Freeze and identify the candidate.** Record commit, build inputs/toolchain, pinned Oracle version/hash, exact frontend/helper/Setup/CLI hashes and ZIP SHA-256. Require current Python/source checks, compiled native tests and independent archive verification. Verify the ordinary diagnostic ZIP still excludes the privileged helper and CLI adapter. Do not change an archive allowlist merely to add this checklist.
- [ ] **Revalidate the system boundary.** Candidate-specific helper/privilege/session, orphan/interrupted recovery, real guest/cleanup and relocation checks must pass. Retain evidence of refusal for wrong build/owner, changed or missing receipts, live owners/guests, unknown observations and foreign resources. Attempt journals must distinguish intent, worker exit and completed helper checks; truncation/corruption must not permit replay or cleanup.
- [ ] **Complete both isolated workstation records below.** No interactive Windows 10/11 approval/cancellation result is currently accepted. Hosted Windows Server refusal or an already-elevated fixture does not fill this gate.
- [ ] **Resolve the known blockers above with independent review and candidate-specific tests.** Record operational failures both before deletion and after partial payload removal. Without a supported safe outcome, do not promote the candidate.
- [ ] **Review recovery and deployment limits.** Review the privileged helper and deployment boundary, retained-child waits, failure messages and the exact manual recovery instructions. A timeout/FAILED result must never imply completed cleanup. Record unsupported configurations and residual resources explicitly. If a required scenario is uncertain, keep the candidate experimental.
- [ ] **Review distribution and release wording.** Verify dependency/license notices and package contents; no bundled Oracle/Extension Pack or implicit extra-driver installation. State unsigned-publisher limitations honestly. Obtain explicit merge/release approval only after reviewing the collected evidence; do not describe passing tests as a guarantee against host damage.

## Independent isolated Windows 10 and Windows 11 records

Create **two separate results**, one for Windows 10 22H2 x64 and one for Windows 11 x64. Record the exact OS build, updates, hardware/virtualization setup, security settings, user/token type, candidate hashes and snapshot identifier. If nested virtualization is unavailable, use dedicated disposable hardware; do not substitute the daily-use workstation. Begin with no installed VirtualBox or foreign VBox resources. Test foreign-resource refusal only in a separate disposable snapshot.

For **each** host, retain before/after service/process/driver observations, protected helper receipts/journals, ordinary diagnostics, relevant screenshots and guest UUID/disk/snapshot evidence. Service JSON alone is not ownership proof or a complete system audit. Mark each step PASS, FAIL or NOT RUN and link its artifacts.

1. **Ordinary mode and Russian UI.** Normal double-click remains diagnostic and non-elevated. Inspect RU -> EN -> RU, explicit saved language, long captions, failure text and file pickers at 100%, 150% and 200% scaling. Read-only actions must not create portable folders or start Oracle. Verify pinned file-only setup without MSI/driver execution, preservation of existing app64, and non-overwriting backup/restore into a fresh root.
2. **Real consent.** From the same administrator's medium split-token session, deny Start UAC and verify no system effects. Then approve Start and verify the helper alone is elevated while Manager/guest remain non-elevated. Leave one consent request pending long enough to show it remains pending, then cancel it: elapsed time must not manufacture completion. Do not force-kill the worker. A different-user standard-account elevation is unsupported and must not be advertised as accepted.
3. **One real guest, two cycles.** Create only a disposable local VM. Boot, write and read guest data, take/verify a snapshot, close/reopen Manager while the guest runs and confirm the guest survives. A second controller and Finish while a guest is active must refuse destructive cleanup. Gracefully shut down, Finish, verify exact-owned VBoxSup/VBoxSDS removal and unchanged VM identity/data; repeat a complete session. Save `ru`, verify actual Russian Oracle captions; save `en` for the next full start. Auto/temporary language and live-guest reopen must not overwrite Oracle's independent preference.
4. **Denied Finish and explicit recovery.** Deny cleanup UAC: resources must remain visibly pending, not reported removed. Retry Finish successfully. Separately follow the documented confirmed-leave/relaunch/Recover path and verify one-shot exact-owned cleanup. Repeat recovery must not acquire fresh authority. For approved controlled interruption fixtures, require the matching acquisition receipt; missing, changed, forged or uncertain evidence must stop cleanup. Do not improvise forced kills, power cuts, XML edits or `sc delete` commands.
5. **One-VM moved-root repair.** With the guest off and owned resources cleaned, move a disposable Unicode root and separately exercise a test drive-letter change. Keep the original verified full backup. Folder-picker Cancel and confirmation No must leave registration/resources unchanged. Confirmed repair must preserve VM/snapshot UUIDs and base/differencing disk hashes, with no `--delete`. Already-local repair is a no-op. Register-only recovery requires the same original backup and validated missing-entry state; exercise it only through a controlled test fixture, never by editing production XML. Wrong UUID, changed backup/media, present old path, external disk or unknown host evidence must refuse repair.
6. **Refusal and final host condition.** In separate snapshots, check existing VirtualBox/foreign VBox resources and denied/unreadable observations: refuse rather than replace, delete or guess ownership. Compare the final host with its baseline; investigate unexpected residual services, drivers, processes or changes and confirm a normal host restart. Preserve failed-session evidence, then restore the disposable snapshot if safe cleanup cannot be established. A successful reboot is not a whole-system integrity proof.

## Explicitly outside this release

Multi-VM mutation/transaction recovery, USB passthrough, bridged-network driver installation, automatic updater/rollback, saved-state migration and physical cross-host portability are not acceptance targets for this minimal release. Existing multi-VM inspection/backup results grant no repair authority. Do not simulate batch repair by repeating the one-VM action. Arbitrary power-loss recovery and a guarantee of safety on a primary OS are not claimed.

## Read-only partial-cleanup inspection

[Developer reconciliation](CLEANUP-RECONCILIATION.md) compares surviving app64/code
bytes against the pinned inventory and reports missing files. It does not query
Windows state or authenticate ownership, and always denies resume authority.
It adds no runtime action and does **not** close the operational-retry blocker.

## Owner-bound private-payload continuation (candidate)

The fixed helper now has a separate continuation branch for deletion of its
original protected app64/code files, after a new durable system-teardown checkpoint.
It uses the same paired helper/frontend, original owner generation, retained
Windows object identities and a flushed BEGIN/DONE journal. It cannot call
PowerShell or repeat a service, driver or package operation. Only the exact
original files and expected empty directories are eligible; user VM data and
acquisition/cleanup receipts are preserved. See the [design and limits](designs/owner-bound-cleanup-resume.md).

Source gates are implemented; exact-candidate native Windows and disposable
system-effect CI must pass before this increment is accepted. File-only journal
and plan tests do not substitute for those Windows checks. The controlled fixture
covers AfterFirstDelete with same-controller Finish and BeforeMarker with a new
controller Recover. Neither is interactive workstation UAC or physical power-loss
acceptance. Missing/torn checkpoint or journal, changed/recreated objects, uncertain
observations, an abandoned mutex, and a crash before the checkpoint remain blocked.
Never remove or reconstruct evidence to force retry. Finish sessions with their
original paired build before upgrading; protocol/build mismatches deliberately refuse.
