# Lifecycle coordination implementation plan

Execution: inline continuation authorized by the user. Start at `7796217f5cafe4e68485aaba6d874536b9ed51c4`. Preserve historical master, archive, upstream reference and draft PR #7. No release, real service mutation, driver installation or VM execution.

## Contract

Implement a native AutoIt coordinator around the existing LifecycleJournal. Trusted compiled callbacks provide fresh observations, exclusive-acquisition/release receipts and durable snapshot storage. Callback names are not accepted from files/CLI; callback return types and operation context must be validated. Callbacks are trusted program code, not a sandbox for hostile extensions.

A resource has a kind, logical name, expected descriptor and a capability ticket obtained only after an exclusive successful acquisition. A matching observation alone is not ownership. The adapter must bind its ticket to the actually created resource and verify that binding on subsequent probes. Real Windows effect adapters are NOT provided in this package.

Before every effect: persist intent, then re-probe. After every effect: validate the receipt, re-probe and persist the resulting journal. Unknown outcomes, identity/ticket conflicts, or persistence failures freeze the session. Never infer exclusive acquisition from absent-before/present-after. Known no-effect acquisition and release failures remain distinct from uncertainty. Cleanup is reverse-order, one attempt per call, with no automatic retry.

Cancellation prevents new acquisitions. An action already started must finish observation/persistence before cancellation is reported; cleanup of confirmed owned resources remains available. Reentrant calls cannot dispatch effects. Sessions and sequence numbers are bounded. Snapshots remain diagnostic-only, with no resume/import authority.

Default persistence uses the existing exclusive, flushed journal writer in a caller-provided private directory. It does not claim protection from a same-account/admin actor changing directory topology, power-loss-proof filesystem transactions, or preemption of a blocking callback. Future privileged adapters must have their own bounded execution and retained native capabilities.

## Tasks

- [ ] Add native tests and interface-only checkpoints; observe failures in hosted Windows without invoking real effects.
- [ ] Implement acquisition/release coordination, cancellation, reentrancy protection, receipt validation and storage-failure barriers.
- [ ] Normalize read-only Windows observations without issuing ownership tickets; test a real existing service and the current process.
- [ ] Exercise private-file persistence, races, partial/unknown results, changed resources, retries and malformed callbacks; rerun all native/Python/build/preparation checks.
- [ ] Record exact code/run identities and limitations, update the existing draft PR, preserve protected refs.

## Files and verification

Create `source/LifecycleCoordinator.au3`, `source/CoordinationObservation.au3`, `tests/native/test_coordinator.au3`, focused regression tests as needed. The launcher entrypoint stays unchanged and does not include effect adapters.

Existing native runner automatically discovers `tests/native/test_*.au3`. Run `scripts/test-native.ps1` with the pinned signed AutoIt compiler on hosted Windows; run `python -m unittest discover -s tests -v` on Linux/Windows. Use actual CI logs and source readback, not compilation alone, as completion evidence.

## Review focus

Persistence failure after a successful effect; resource replacement after intent storage; forged or context-mismatched receipts; cancellation during an effect; a stale snapshot or query-only Windows observation incorrectly granting cleanup authority.
