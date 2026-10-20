# Runtime safety model and review gates

Status after code/test checkpoint `1e952e4`: file preparation, native lifecycle policies, read-only Windows adapters and synthetic-effect coordination are implemented. Actual privileged service/process effect adapters, driver mutation and VM launch remain NOT implemented. Windows 11 x64 / VirtualBox 7.2.x runtime compatibility is unverified.

## Compiled boundary

The former launcher is preserved unchanged in `source/legacy/Portable-VirtualBox.au3.disabled`. The preview entrypoint does not include the old installer/updater, COM registration or service commands. It exposes diagnostic/test commands and otherwise exits. No `#RequireAdmin` is active. The new coordinator is compiled in dedicated native tests but is not wired into the preview entrypoint.

The active-source pattern audit and bounded literal API contract are enforced in CI. Zero matches is not a whole-program security proof. Original files and historical instructions must not be used to bypass the preview boundary.

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

## Journal and coordinator contract

`LifecycleJournal.au3` models acquisition and reverse release. It refuses pre-existing resources, unknown initial probes, duplicate identifiers, out-of-order cleanup, foreign sessions, changed identities and unknown outcomes. Pending/uncertain operations block further cleanup. Known failed creation is never ownership.

`LifecycleCoordinator.au3` persists intent before each effect, re-probes after storage, validates the returned receipt and confirms the resulting observation before persisting success. Receipt identity includes session, operation, kind/name, descriptor, verb and an exclusive-acquisition ticket. The eventual trusted effect adapter must bind that ticket to an actual native capability and revalidate at the effect boundary; syntax alone cannot prove ownership.

Known no-effect acquisition failures require confirmed absence. Retryable no-effect release failures require the same identity/ticket still present. Uncertain outcomes or persistence failures freeze the session. Cancellation blocks further acquisition while allowing confirmed-owned cleanup. Reentrant calls are refused. There is no implicit retry, snapshot resume or active-session import.

The callback interface accepts trusted compiled function references only, not names from input. Checked invocation preserves error flags and isolates ByRef request modification. It is not a sandbox, an elevation boundary or a way to preempt a blocking callback. Future effect adapters need bounded execution independently.

Snapshots are bounded UTF-8 TSV with a completion footer. Exclusive CREATE_NEW writes refuse existing files and flush data. Sequenced coordinator snapshots do not overwrite earlier evidence. The caller must provide an existing private trusted directory; the writer also rejects a reparse-point directory leaf. These checks do not guarantee resistance to same-account/admin topology changes or power-loss-proof transactions. Loaded snapshots are always diagnostic READONLY, with formerly active rows UNCERTAIN. A saved token never restores cleanup authority.

Native tests run compiled AutoIt code with synthetic effects, private journal files, real query-only self/child observations and a built-in service read. Test children are private copies that exit naturally. Tests do not create, stop or delete services, run Oracle payloads or install VBox drivers.

## Required before actual startup

1. Implement ownership-bound process creation/effect adapters with retained native handles, tested first on harmless private children. Preserve unrelated processes and reject stale/reused identities.
2. Add separately reviewed privileged service adapters with durable intent, bounded waiting, cancellation and ownership revalidation. A read-only observation, callback receipt string or saved journal cannot authorize an effect by itself.
3. Never delete pre-existing system DLLs, global installers, VM logs, XML backups, disks or snapshots. Never terminate all matching process names.
4. Validate driver/COM/dependency layout in the prepared app64 files. Retain backup/rollback evidence for any explicitly authorized VM migration.
5. Perform isolated Windows 11 driver/VM acceptance: coexistence, repeated launches, failure, cancellation, networking/USB, shutdown and relocation. Do not test against the only copy of valuable VMs.
6. Review redistribution/dependency terms separately; Extension Packs are optional and never silently installed.

## Review and publication

Exact counts/run links are in [EXECUTION-2026-10-20-coordinator.md](EXECUTION-2026-10-20-coordinator.md). Review is author-side source inspection, regression tests and artifact readback, not independent security review. Compilation is not deterministic reproduction or release readiness. Keep PR #7 draft and preserve master/archive until explicit merge/release gates are met.
