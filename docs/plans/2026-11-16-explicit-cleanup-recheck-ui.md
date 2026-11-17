# Explicit cleanup recheck UI implementation

1. Add failing native ticket/selection and source wiring tests.
2. Add action-bound UI ticket only for confirmed separated cleanup worker exit 70.
3. Consume before explicit same-action request, preserve lock/gates and normal failure.
4. Localize eligible retry button/status without reopening Start/rebind/Manager.
5. Run source/full suite, independent review and actual Windows native/UI/helper gates.

No helper/worker permission, marker, ledger or system command changes are in scope.
Retain original failure and all evidence; a new click is only a request to recheck.

Review correction: a CLI-gate failure must not move an existing retained worker
out of a polled phase. The retry-start uncertainty path now updates only detail,
without a second gate transition after launch. The shared state function preserves
an existing/requested worker phase whenever a retained child exists, and Tick uses
the same explicit phase inventory. Before launch or after handle release, the same
gate failure remains FAILED, never CLEAN. Added pure transitions plus an actual
harmless seven-second child with contradictory observation metadata and a synthetic
broken gate to exercise the persistent-UNKNOWN path. No child termination or
system operation is used by this test. Windows execution remains pending.

Cancellation correction: cancelling a recheck after a previous unknown/partial
cleanup must not take the ordinary CLEANUP_DECLINED path (which may reopen CLI).
Track the in-flight recheck action separately. Confirmed exit 1223 restores only
that prior action ticket, stays FAILED, keeps the session mutex and CLI closed.
Ordinary first-request cancellation is unchanged. Added Finish/Recover policy
cases and an actual harmless retained exit-1223 child; this is not interactive UAC
acceptance. Source regression was RED before the distinction and GREEN afterward.

Final local snapshot: 484 tests, seven expected platform skips, no failures
(156.738 seconds). Active-tree and diff checks pass. Independent review accepted
both retained-polling and cancelled-recheck corrections. Native AutoIt compilation,
actual harmless-child controller regressions and existing Windows lifecycle jobs
remain required at the published source. No interactive UAC acceptance is claimed.
