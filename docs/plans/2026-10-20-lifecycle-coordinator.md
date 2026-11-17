# Lifecycle coordination implementation plan

Execution: inline continuation authorized by the user. Started at `7796217f5cafe4e68485aaba6d874536b9ed51c4`. Preserve historical master, archive, upstream reference and draft PR #7. No release, real service mutation, driver installation or VM execution.

Status: this bounded coordinator package is complete at code/test commit `1e952e40159a15a77dae7e1cec0d5b3ed43976f6`. It does not complete a privileged runtime. Evidence and limitations are in [the execution report](../EXECUTION-2026-10-20-coordinator.md).

## Contract

Implement a native AutoIt coordinator around LifecycleJournal. Trusted compiled callbacks provide fresh observations, exclusive-acquisition/release receipts and durable snapshot storage. Callback names are not accepted from files/CLI; callback return types and operation context are validated. Callbacks are trusted program code, not a sandbox for hostile extensions.

A resource has a kind, logical name, expected descriptor and a capability ticket obtained only after an exclusive successful acquisition. A matching observation alone is not ownership. The adapter must bind its ticket to the actually created resource and verify that binding on subsequent probes. Real Windows effect adapters are NOT provided in this package.

Before every effect: persist intent, then re-probe. After every effect: validate the receipt, re-probe and persist the resulting journal. Unknown outcomes, identity/ticket conflicts, or persistence failures freeze the session. Never infer exclusive acquisition from absent-before/present-after. Known no-effect acquisition and release failures remain distinct from uncertainty. Cleanup is reverse-order, one attempt per call, with no automatic retry.

Cancellation prevents new acquisitions. An action already started finishes observation/persistence before cancellation is reported; cleanup of confirmed owned resources remains available. Reentrant calls cannot dispatch effects. Sessions and sequence numbers are bounded. Snapshots remain diagnostic-only, with no resume/import authority.

Default persistence uses the existing exclusive, flushed journal writer in a caller-provided private directory. It does not claim protection from a same-account/admin actor changing directory topology, power-loss-proof filesystem transactions, or preemption of a blocking callback. Future privileged adapters must have their own bounded execution and retained native capabilities.

## Completed tasks

- [x] Add native tests and interface-only checkpoints; observe failures in hosted Windows without real effects. Initial coordinator checkpoint: 43 failed assertions of 54; storage/normalization checkpoint: 12 failed of 32.
- [x] Implement acquisition/release coordination, cancellation, reentrancy protection, receipt validation and storage-failure barriers.
- [x] Normalize read-only Windows observations without issuing ownership tickets; test a real existing service and the current process.
- [x] Exercise private-file persistence, races, partial/unknown results, retries and malformed callbacks; rerun native/Python/build/preparation checks.
- [x] Record exact code/run identities and limitations; maintain the existing draft review vehicle and preserve protected refs.

## Files and verification

Implemented `source/LifecycleCoordinator.au3`, `source/CoordinationObservation.au3` and five focused native harnesses. Added bounded Python source contracts, an aggregate native runner, and a regression-driven token validation fix in `WindowsProcessProbe.au3`.

Final native suite: 351 assertions in 9 compiled Windows harnesses, zero failures. Python: 62 discovered, Linux 57 pass/5 Windows-native skips; Windows 61 pass/1 symbolic-link privilege skip. Core build, native suite and real Oracle preparation workflows all pass. Counts do not establish real driver/VM behavior.

## Rulings and review findings

- Validate callback invocation through Call/FuncName after a wrong-arity native timeout; preserve error flags and isolate ByRef request writes. Only validated function references are accepted, not arbitrary input names.
- Reject nonpositive/out-of-range coordinator and observer tokens before AutoIt map lookup after reproducing negative-token native crashes. Keep the regression tests.
- Aggregate bounded native harness failures so one fault does not suppress other evidence. Remove temporary tracing after diagnosis.
- Keep new coordination disconnected from the preview entrypoint; synthetic effects do not justify enabling inherited mutations.

## Next package

Implement an ownership-bound process-launch adapter for harmless private test children only: exclusive creation evidence, retained native handles, bounded wait/cleanup and journal coordination. Demonstrate no effect on unrelated or reused process identities. Do not launch Oracle payloads, mutate VBox services, remove preview protections or publish a release. Privileged service/COM/driver integration and isolated Windows 11 VM acceptance remain separate later packages.
