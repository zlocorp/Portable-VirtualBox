# Explicit same-session cleanup recheck in the Manager UI

## Gap

The helper now supports a fresh Finish/Recover after read-only preflight refusal,
but the GUI turns every nonzero worker exit into FAILED and disables both actions.
The direct-helper disposable fixtures therefore do not prove same-window usability.

## Choice and authority boundary

Retain FAILED, the existing resources/locks, original error text and existing exit
confirmation. Record an internal action ticket only when a separated Finish or
Recover request has a confirmed worker exit 70. No Prepare/configure/unknown/live
worker outcome receives a ticket. An explicit button click may consume the ticket
and request the same fixed helper action with the same controller/cycle/former PID.

The ticket is UI eligibility, not system authority or a preflight-success claim.
The protected helper must revalidate everything. Existing admission markers and
uncertain effects continue to refuse replay. No ledger/marker deletion, no automatic
request, no service observation used as permission, no bypass of UAC or CLI gates.

A pure selection predicate checks FAILED, separated mode, retained session mutex,
confirmed EXITED/handle-zero worker, exit 70 (or a verified cancellation of an
already ticket-bound recheck) and action/session identity. A consume
function clears the ticket and transitions to the matching consent phase before
launch; a second click cannot produce another request. Cancellation of this new
request returns to FAILED with the original mutex and closed CLI admission, never
the ordinary first-cleanup CLEANUP_DECLINED path. The same action-bound ticket is
restored for a later explicit click only. Transition/launch failure
stays fail-closed. The actual retry entrypoint also requires the existing supported
host/root and ordinary split-token checks. Finish requires an owned prepared
session; Recover requires its retained former PID, never fresh discovery/adoption.

The existing Finish button becomes 'Retry cleanup checks' only when eligible.
Russian/English status explains that prior/uncertain cleanup may still be refused.
Start, rebind and reopen remain disabled. Closing retains the existing FAILED exit
warning; this change does not declare any failed cleanup safe or complete.

## Verification required

Native AutoIt predicate/ticket tests include wrong action, Prepare/other phases,
unknown/live worker, exit 0/1223/other errors, missing mutex, missing ownership,
foreign/self original PID, repeated click and phase transition. A harmless retained
worker exit-70 fixture exercises actual controller failure observation, not just a
source-string test. Source contracts bind UI invocation, reset ordering and texts.
Existing actual Finish/Recover refusal/retry fixtures and post-admission refusal
remain required; GUI state tests do not replace protected helper authority tests.

Full integrated suite, compiled Windows native/UI regressions and independent review
are required. Interactive Windows 10/11 UAC/whole-user-flow acceptance stays open.
