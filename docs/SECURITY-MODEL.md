# Runtime safety model and review gates

Status after executable-code commit `d83e6ff`: preparation tools and native policies implemented; privileged runtime and VM launch NOT implemented. Target Windows 11 x64 / VirtualBox 7.2.x remains unverified as a virtualization combination.

## Compiled boundary

The former launcher source is preserved unchanged in `source/legacy/Portable-VirtualBox.au3.disabled`. The new entrypoint does not include it, the old installer/updater functions, COM registration, or service commands. It exposes diagnostic/test commands and otherwise exits. No `#RequireAdmin` is active in the preview entrypoint.

The active-source pattern audit is enforced in CI; the quarantined source has a separate report. Zero pattern matches is not a whole-program proof of safety. The remaining original files and old instructions must not be used to bypass this boundary.

## Implemented preparation safeguards

Downloads require explicit versions, official HTTPS URL validation, bounded response sizes and verified SHA-256; output publication refuses overwrite, including tested destination races. Owner-scoped temporary files do not permit deleting another operation's partial file. The read-only XML inventory checks encoding, namespace, DTD/entity rejection, registry scope and Windows path ambiguity; no VM XML is rewritten.

The passive Oracle extractor validates PE bounds and coherent neutral/en-US RCDATA package resources. It requires an exact trusted wrapper SHA-256, safe unique filenames and expected package structure, creates a new staging directory, and retains an incomplete marker after partial failure. It does not execute the wrapper or MSI. The hosted inspection additionally validates Oracle Authenticode, exact MSI product/version/x64 metadata, unchanged MSI bytes and unchanged VBox service registry entries. That registry snapshot is NOT a running-service state audit.

Extracted MSI and CAB files are not a ready-to-run application tree. No extracted Oracle executable is invoked. CI retains metadata, not Oracle redistributable payloads or Extension Packs.

## Implemented lifecycle policy, not a privileged adapter

`source/LifecycleJournal.au3` models acquisition and reverse-order release. It refuses pre-existing resources, unknown initial probes, duplicate resource identifiers, out-of-order cleanup, foreign sessions, changed identities, and unknown operation outcomes. Pending or uncertain operations block further cleanup. Known failed creation is never ownership.

`_PJ_Confirm(..., False, True)` requires the caller to have verified ABSENCE after failure. An error exit code alone is not that proof. `_PJ_CompleteCleanup(..., False, False, True)` is retryable only when the adapter has verified the original resource remains unchanged. These are caller contracts; the journal does not query Windows for them.

Snapshots are bounded UTF-8 TSV with a completion footer. Exclusive `CREATE_NEW` writes refuse existing output files and flush written data. Failed writes preserve evidence. `_PJ_SaveNew` requires an existing private, non-reparse parent directory supplied by the caller; it is not a complete privileged transaction coordinator. Disk snapshots are inspectable but always READONLY; previously active resource rows become UNCERTAIN. Matching a saved token cannot restore cleanup authority.

The process policy no longer accepts PID equality alone. It requires a retained-handle assertion and matching PID, creation identity and executable identity. It is a pure comparator, not a handle acquisition or termination implementation. The future adapter must bind these observations to a retained handle and prevent reuse races.

Native tests exercise the real AutoIt implementation with synthetic identities and private temporary journal files. They do NOT create, stop or delete Windows services.

## Required before enabling actual startup

1. Inspect existing installations/processes/services before privilege escalation. Fail closed on ambiguity, unsupported hosts and unowned resources. Hybrid mode needs separate explicit design and tests.
2. Implement an OS adapter that obtains authoritative identities, persists intent before effects, checks each result and revalidates ownership at cleanup. Handle interruptions and partial outcomes conservatively.
3. Never delete pre-existing system DLLs, global installers, VM logs, XML backups, disks or snapshots. Never terminate all matching process names. Do not infer ownership merely from service existence, name or a recorded PID.
4. Stage extracted application files without installing the MSI, then validate the actual driver/COM/dependency layout. Retain rollback data before any explicitly authorized migration.
5. Test installed-VBox coexistence, Windows 11 driver lifecycle, first and repeated runs, failure and cancellation, networking/USB, VM shutdown and relocation on an isolated disposable environment. Do not use the only copy of valuable VMs.
6. Review dependency and Oracle redistribution terms separately. Extension Packs remain optional and are not silently downloaded or installed.

## Review and publication

Current verified counts and run links are in EXECUTION-2026-10-19.md. Review during this iteration was author-side source inspection plus automated tests, not independent review. Successful compilation is not deterministic reproduction, runtime acceptance, or release readiness. Keep PR #7 draft and preserve master and archive refs until explicitly authorized release/merge gates are met.
