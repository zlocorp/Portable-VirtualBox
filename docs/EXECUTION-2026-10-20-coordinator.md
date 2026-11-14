# Execution report: journaled lifecycle coordination

Date: 2026-10-20. Status: **native coordinator implemented and tested with synthetic effects; actual privileged operations and VM startup remain disabled**.

## Scope and exact checkpoint

The iteration began at `7796217f5cafe4e68485aaba6d874536b9ed51c4` on `dev/modernization-2026`. The completed app64 preparation and read-only Windows adapters were preserved, not reimplemented. Draft [PR #7](https://github.com/zlocorp/Portable-VirtualBox/pull/7) targets `work/upstream-baseline-2026`, not historical master.

Verified executable-code/test commit: `1e952e40159a15a77dae7e1cec0d5b3ed43976f6`.
Verified tree: `741ef72bad44928edcd6eab13b5bf86f3f8c10ef`.
The hosted PR checkout `d407974364b7b07d7eab8ba59e9649d4579dc148` has exactly that tree. This temporary GitHub CI merge reference is not a merge into master. Later report/README/plan changes are documentation only.

No user PC, real service creation/deletion, VBox driver install, Oracle payload execution, VM execution, release or master merge was used.

## Implemented behavior

`LifecycleCoordinator.au3` connects the existing native journal to trusted compiled probe, effect and storage callbacks. Before dispatching an effect it persists the intent and rechecks the resource. Afterwards it validates a typed receipt, obtains a fresh observation and persists the result. Receipts bind the session, operation index, resource kind/name, descriptor, verb and acquisition ticket. A matching path/name or absent-before/present-after observation alone is not ownership.

Confirmed resources are released in reverse acquisition order. Each call makes at most one release attempt. A known no-effect failure is retryable only after confirming the same resource/ticket; there is no automatic retry. Unknown outcomes, changed identities, malformed receipts and persistence failures freeze the session instead of guessing cleanup authority.

Cancellation prevents new acquisitions. An already dispatched action is still observed and recorded before cancellation is returned; cleanup of confirmed resources remains possible. Reentrant calls return BUSY. Sessions and sequence numbers are bounded. Compiled function references are validated; string callback names are refused. A checked invocation boundary preserves callback error flags, catches argument-count failures and isolates ByRef modifications from the caller's request.

`_PC_SaveFile` requires an existing private directory. It validates the session/journal/snapshot and local path, rejects a reparse-point directory leaf, then exclusively creates a numbered UTF-8 snapshot through the existing flushed journal writer. Existing files are never replaced. Missing directories are not silently created. Recovery remains diagnostic-only; saved snapshots cannot create active coordinator sessions or restore cleanup authority.

`CoordinationObservation.au3` normalizes read-only service/process observations with typed fields and length-delimited descriptors. Denied/invalid/unknown observations remain unknown. The normalizer always returns an empty ticket, including when an input map supplies a forged ticket. Native tests connect it to actual RpcSs and retained self-process observations without modifying those resources.

The coordinator is NOT wired into the preview entrypoint. No real Windows effect callback is included. Test callbacks simulate creation/release in memory; file persistence and query-only Windows calls are real.

## Regressions found and fixed

- The initial interface checkpoint `9075a4e` compiled and failed 43 of 54 coordinator assertions, establishing the red baseline in [run 39371552987](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39371552987).
- Storage/observation interface tests initially failed 12 of 32 assertions in [run 39371951603](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39371951603). Final implementations pass all 32, including real exclusive files under a Cyrillic path.
- Instrumented native execution localized an access violation to a negative coordinator token reaching the integer-key map lookup. Validating type and positive issued-token range before map access fixed it; invalid-token regressions remain.
- Wrong-arity direct function-reference calls caused a native harness timeout. A checked Call/FuncName boundary now reports that programming error through error flags; dedicated callback tests verify argument-count failure, error preservation and request isolation. This does not sandbox callbacks or preempt a callback that blocks internally.
- Review found the same negative-token map boundary in the earlier Windows process observer. A separate native regression reproduced exit -1073741819 in [run 39373513242](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39373513242) before the final fix. Read/close now check token range first; invalid inputs leave the valid retained handle usable. The final regression passes 17 assertions.

Temporary tracing harnesses and verbose debugging were removed. The native runner now completes every bounded harness and aggregates failures instead of hiding later suites after the first failure.

## Executed verification

All three PR workflows passed at the exact code checkpoint:

| Check | Result | Evidence |
| --- | --- | --- |
| Core CI | Python suite, source guards, x64 compile, diagnostic commands, blocked Server preflight, spaces/Cyrillic build path pass | [39373693467](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39373693467) |
| Native AutoIt | 351 assertions in 9 compiled harnesses; zero failures | [39373693439](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39373693439), job 118466961847 |
| Windows Python and actual Oracle preparation | 62 tests: 61 pass, 1 symbolic-link privilege skip; verified 185 app64 files / 247738522 bytes | [39373693485](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39373693485), job 118466961906 |
| Full local Python rerun on downloaded committed sources | 62 tests: 57 pass, 5 Windows-native skips, zero failures | Verified source artifact below |
| Active-entrypoint audit | Zero matched dangerous operations, enforce exit 0 | Core CI and local rerun |

Native counts: coordinator 54; coordinator edge cases 78; storage/Windows normalization 32; callback boundary 6; process-token regression 17; prior lifecycle 56; runtime policy 11; Windows observations 77; Windows edge cases 20. Total 351, with 187 new assertions. These are assertions, not 351 independent executables. Python platform results must not be added as unique tests.

Preparation again used the pinned Oracle 7.2.20 package, checked its signature/checksum, independently rehashed the staged files and verified unchanged wrapper/MSI/CAB inputs and inspected VBox service registry entries. No Oracle installer, MSI action or extracted executable was run. This is still file preparation, not driver/VM acceptance.

## Source readback and review

The source snapshot from [run 39373689321](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39373689321), artifact 12242014535, was downloaded and verified:

- Outer ZIP SHA-256: `938700ccc4db7a2f58d3a6a989c4c2fbc6654fc4a7fc4cfebdf414baf3a8d4c5`.
- Inner source.zip SHA-256: `4c160c347825d173c3336323cec7bdf7502d108090d1687eee1dbf513daa064a`.
- COMMIT.txt matches `1e952e40159a15a77dae7e1cec0d5b3ed43976f6`; ZIP CRCs and extraction paths checked.
- The full Python suite and entrypoint audit were rerun against these committed sources. Temporary diagnostic harness absence was confirmed.

Review was author-side source/contract inspection, regression execution, hosted native tests and source readback. No independent reviewer, complete security audit, deterministic AutoIt binary output or standard-user Windows 11 coverage is claimed.

## Remaining limitations and next bounded package

The coordinator supplies ordering and failure decisions, not an OS security capability. A future trusted effect adapter must exclusively acquire resources, retain the relevant native capability, bind tickets to that acquisition and revalidate immediately at the actual operation. A service snapshot is not atomic ownership; a read-only process handle does not prove launch ownership. A forged or buggy trusted callback cannot be made safe by receipt syntax alone.

Callbacks are synchronous trusted program code. Internally blocking callbacks, process crashes during dispatch and power-loss-proof filesystem recovery are outside this implementation's guarantee. Snapshot directories must have trusted private parents; leaf checks do not defeat a same-account/admin actor changing the directory topology. Frozen sessions deliberately retain uncertain resources and evidence rather than automatically deleting them.

Next package: an ownership-bound process-launch adapter exercised on harmless private test children in hosted Windows, with retained native handles, exact acquisition evidence, bounded waits and coordinator integration. Keep VBox binaries, services and drivers disconnected. Actual privileged service adapters, dependency/COM validation, VM start/stop, migration, networking/USB and isolated Windows 11 acceptance remain later gates.
