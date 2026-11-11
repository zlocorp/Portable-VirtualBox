# Runtime safety model and review gates

Reviewed against `a98d0f0` (2026-11-11). The ordinary diagnostic launcher, explicit workstation ALPHA and disposable-host CI are different execution modes. A fixed-action privileged helper and real Alpine guest boot/VDI readback already exist; **interactive Windows 10/11 UAC and workstation driver acceptance are still pending**. This is a description of implemented boundaries, not a security certification or release approval. See [minimal one-VM release gates](RELEASE-GATES.md).

## Compiled and package boundaries

- **Ordinary preview:** normal double-click and documented diagnostic/preparation CLI do not install drivers, start VMs or mutate Windows services. Explicit file setup, preferences and offline backup/restore can write portable files. The diagnostic ZIP excludes the privileged helper and portable Oracle CLI adapter. No blanket `#RequireAdmin` is active; the legacy launcher remains disabled in `source/legacy/Portable-VirtualBox.au3.disabled`.
- **Explicit ALPHA:** a separate non-release package exposes `--alpha-runtime` with an exact-build helper. The frontend requires a medium UAC split token on an x64 Windows 10/11 workstation; it does not support over-the-shoulder elevation to a different administrator SID. Manager and guests run non-elevated. Driver/service effects require a separate `runas` consent request. Normal double-click remains diagnostic even with the ALPHA package present.
- **CI experiments:** compiled main-launcher and separate test entrypoints exercise real Manager/guest sessions and exact-owned cleanup on disposable Windows Server. GitHub markers and temporary-root restrictions are accidental-use guards, not cryptographic authority. CI and ALPHA helpers are distinct pinned build flavors with separate protected stores; CI markers cannot turn the ALPHA helper into a Server-enabled build.

The active-source pattern audit and bounded literal API contract run in CI. Zero matches is not a whole-program security proof. Signed Oracle payloads and matching build hashes do not make the unsigned launcher a trusted publisher or authorize installation on a valuable host.

## Fixed-action privileged boundary

`PrivilegeBoundary.au3` and `privilege/SessionHelper.Main.cs` implement only `Prepare`, `Finish` and `Recover`, with numeric controller/cycle identities (and the former controller for recovery). The helper does not accept arbitrary commands, caller-selected scripts or effect paths. It verifies the build-paired frontend, retained process identity, token/user/session and protected session evidence. Runtime payload hashes are checked against compiled pins; elevated scripts are embedded and staged into protected directories. A privileged mutex serializes effects. These controls do not defend against an already-compromised administrator or kernel.

Protected receipts are under `%ProgramData%/PortableVirtualBox.Alpha` for ALPHA and `PortableVirtualBox.Experiment` for CI. Cleanup requires exact owned resources and current identity evidence, not just a matching service name, path or saved PID. Foreign installations, services, driver collisions, changed receipts and unknown observations block progress. Recovery is a separate explicit one-shot action for a proven departed controller; interrupted preparation needs its corresponding protected acquisition checkpoints. An operation interrupted before a trustworthy receipt cannot be guessed into ownership.

**Known everyday-release blocker:** cleanup/recovery attempts can create one-shot proof/cleanup directories before resource deletion. An operational refusal or transient error can then block another attempt even if nothing was removed. After partial `RemoveVerifiedPayload` cleanup, the next invocation still requires the full inventory and can refuse. Thus retained evidence/resources are fail-closed behavior, **not successful rollback or a supported retry guarantee**. A cancelled UAC request before helper execution is different from a failed helper attempt. General retryable recovery needs a separately reviewed fix and acceptance; until then use only disposable hosts and restore their snapshots if exact cleanup cannot be established.

There is no force-kill fallback. Managed processes use retained handles and graceful close requests; closing Manager does not prove the guest stopped. A live guest, an active command lease or uncertain identity prevents cleanup. `FAILED`, denied UAC and closing a window are not evidence that drivers/services were removed. See the [isolated ALPHA procedure](ALPHA-WINDOWS-TEST.md) for explicit Finish retry and recovery.

## Implemented preparation safeguards

Downloads require explicit versions, official HTTPS URL validation, bounded responses and SHA-256 verification; publication refuses overwrite, including tested destination races. Owner-scoped temporary cleanup cannot delete another operation's partial file. XML inventory checks encoding, namespace, DTD/entity rejection, registry scope and Windows path ambiguity; no VM XML is rewritten.

The Oracle extractor validates PE bounds and coherent neutral/en-US package resources, exact expected hash, safe unique filenames and package structure. It does not execute the wrapper or MSI. Windows preparation reads MSI tables and extracts CAB members into a new staged app64 directory. Host-side CI independently verifies the file inventory, payload hashes, main executable version/signature and unchanged input/registry snapshots. Registry comparison is not a full running-service or whole-system audit. Oracle payloads and Extension Packs are not retained as published artifacts.

## Read-only Windows adapters

- SCM access is limited to SC_MANAGER_CONNECT plus SERVICE_QUERY_CONFIG and SERVICE_QUERY_STATUS. Configuration pointers/UTF-16 strings are bounded to the returned query buffer. Repeated reads reject pending or changed state. Observations are not atomic snapshots of every service property and are not cleanup authority.
- Process handles use PROCESS_QUERY_LIMITED_INFORMATION and SYNCHRONIZE only, without inheritance. PID/FILETIME/image are read from the same retained handle; exit is observed through that handle. Tokens are process-local, non-reused and invalidated on close. Invalid token types/ranges are rejected before native map lookup. These handles do not permit termination.
- Exact integral numeric DWORD PIDs are normalized; strings, fractions and overflow are rejected. FILETIME identity is exact high/low hex, not a rounded floating-point timestamp.
- Error classification is scoped to the open operation: only documented missing-service or missing-key results imply ABSENT. Denied, invalid, partial or changed reads remain UNKNOWN. Preflight blocks UNKNOWN/invalid counts.
- Installation checks examine Oracle/Sun machine keys in both registry views. Native OS product type prevents new Server builds being accepted merely because their build number exceeds Windows 11's threshold.
- Diagnostics print statuses/counts, not image paths or service accounts. An unreadable observation returns a nonzero status.

A queryable process or service may predate the launcher. **Observation is not ownership.** Image path identity is not file-content verification or a signature. A clear preflight can become stale immediately and cannot authorize a future mutation without revalidation. The coordinator requires acquisition receipts separately; its query normalizer always emits an empty ticket. Standard-user-account behavior and deliberately denied DACLs are not fully covered by hosted tests.

## Generic journal and coordinator contract

This generic AutoIt policy layer is distinct from the concrete fixed-action helper and its protected attempt journals below; it is not itself an elevation boundary.

`LifecycleJournal.au3` models acquisition and reverse release. It refuses pre-existing resources, unknown initial probes, duplicate identifiers, out-of-order cleanup, foreign sessions, changed identities and unknown outcomes. Pending/uncertain operations block further cleanup. Known failed creation is never ownership.

`LifecycleCoordinator.au3` persists intent before each effect, re-probes after storage, validates the returned receipt and confirms the resulting observation before persisting success. Receipt identity includes session, operation, kind/name, descriptor, verb and an exclusive-acquisition ticket. Any trusted effect adapter using this generic interface must bind that ticket to an actual native capability and revalidate at the effect boundary; syntax alone cannot prove ownership.

Known no-effect acquisition failures require confirmed absence. Retryable no-effect release failures require the same identity/ticket still present. Uncertain outcomes or persistence failures freeze the session. Cancellation blocks further acquisition while allowing confirmed-owned cleanup. Reentrant calls are refused. There is no implicit retry, snapshot resume or active-session import.

The callback interface accepts trusted compiled function references only, not names from input. Checked invocation preserves error flags and isolates ByRef request modification. It is not a sandbox, an elevation boundary or a way to preempt a blocking callback. Effect adapters need their own execution/lifetime policy; the implemented fixed helper retains a live child rather than claiming a timeout means termination.

Snapshots are bounded UTF-8 TSV with a completion footer. Exclusive CREATE_NEW writes refuse existing files and flush data. Sequenced coordinator snapshots do not overwrite earlier evidence. The caller must provide an existing private trusted directory; the writer also rejects a reparse-point directory leaf. These checks do not guarantee resistance to same-account/admin topology changes or power-loss-proof transactions. Loaded snapshots are always diagnostic READONLY, with formerly active rows UNCERTAIN. A saved token never restores cleanup authority.

## Durable helper attempts versus lifecycle snapshots

`privilege/DurableJournal.cs` records each fixed helper attempt in a new protected file. Verified binding includes action, build/mode, controller PID and creation FILETIME, SID, desktop session, cycle, root/session paths and former-owner identity for recovery. The ordered hash chain contains `INTENT`, `WORKER_EXIT`, then `HELPER_COMPLETE`. Intent is flushed with `Flush(true)` before starting the fixed effect worker. Worker exit is not helper success: final checks and exact persisted-chain readback must also pass.

Writes never overwrite earlier evidence; failed writes/flushes leave the writer uncertain. Readback bounds file/field sizes and rejects malformed encoding, truncation, wrong binding, sequence or chain. The hash chain detects corruption, not a malicious writer with authority over the protected store. It is **diagnostic attempt evidence**, not a VM transaction journal, automatic resume API, cleanup capability or guarantee against physical power loss. There is no journal repair/replay path. This is separate from the generic lifecycle coordinator/snapshot contract above.

## One-VM data and registration boundary

Public `--plan-vm-rebind` inspects; `--prepare-vm-rebind` adds only a verified non-overwriting offline backup. The separate ALPHA **Repair moved VM** action needs explicit confirmation bound to one powered-off VM, UUID, old/new paths, original full backup and action. It requires the old path absent and matching local disk/snapshot data, rechecks before preparation, and uses ordinary-token Oracle unregister **without deletion**, then register. After a verified unregister interruption, the same original backup can permit **register only**, after any required owned-session recovery. Already-correct registration is a no-op; changed/ambiguous data and unsupported saved state are refused.

A backup of `data/` excludes external media and is not a live snapshot. Preserve an independent verified copy. Portable `VBoxManage` is session/build-bound and coordinated with cleanup, but its user-selected Oracle commands can modify data; refusing `unregistervm --delete` does not make it a general safety sandbox. Existing multi-VM inspection/backup/trace features confer no batch repair authority. Multi-VM mutation, USB/bridged-driver management and an updater are outside the minimal release scope.

## What the existing tests establish

Native unit harnesses use synthetic effects and query-only observations; those alone do not prove driver behavior. Separate disposable-host workflows exercise the fixed helper, refusal/forged-receipt paths, interrupted preparation and orphan recovery. The compiled main launcher has also booted Alpine Linux, verified guest-written VDI bytes after teardown/restart, preserved snapshots and completed exact-owned cleanup ([guest evidence](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40407596523)). Four powered-off relocation variants preserved UUIDs and disk hashes ([relocation evidence](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40462477639)); actual Russian/English Oracle captions and screenshots were checked ([localization evidence](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/41537257180)).

These are Windows Server CI observations, not interactive workstation acceptance. The [release gates](RELEASE-GATES.md) separate historical evidence, exact-candidate CI and still-missing Windows 10/11 checks.

## Current system-operation lifetime constraint (2026-10-25)

The CI-bound fixed-action helper no longer requires an optional PowerShell 7 runtime: it invokes the OS-owned x64 Windows PowerShell 5.1 by absolute System32 path. It does not inherit caller PATH or user profiles and still executes only its protected embedded scripts. A script worker that exceeds the expected bound is not abandoned: the helper keeps the process handle and waits for termination before returning an error or releasing its privileged lock; the medium elevation-request worker also waits for the fixed helper to exit rather than treating elapsed time as an exit. This is an **intentional fail-closed wait**, not a claim that Windows operations cannot hang, and a Windows 11 interactive abort/timeout procedure still needs acceptance.

## Remaining release decision

Follow [RELEASE-GATES.md](RELEASE-GATES.md) before promoting any runnable one-VM candidate. In particular, isolated Windows 10 **and** Windows 11 need real approval/cancellation, cleanup retry, safe refusal, data preservation, RU/EN and DPI checks with preserved evidence. Never perform these experiments on the primary OS or the only copy of valuable VMs; do not disable host security to obtain a pass.

Never delete pre-existing system DLLs, installers, VM logs, XML backups, disks or snapshots, and never terminate processes by name. Unknown cleanup status requires inspection or restoration of the disposable host snapshot, not broader privileges or guessed cleanup commands. Review redistribution/dependency terms separately; Extension Packs remain optional and are never silently installed.

Author inspection, passing CI and this document are not an independent security review or proof of production readiness. Keep PR #7 draft and preserve master/archive until explicit merge/release gates are met. Historical execution reports describe their own checkpoints and may contain superseded implementation status; this document and the release checklist describe the current boundary.

## Build changes and existing sessions

An active or incomplete session belongs to its original exact frontend/helper.
Finish or recover using that pair before replacing it. The locale-independent
published-INF receipt fields and new embedded identity script intentionally do
not adopt old sessions that lack them. Retain the original build and protected
evidence; a refusal is not permission to reconstruct receipts, delete markers,
or infer ownership from currently installed driver bytes.
